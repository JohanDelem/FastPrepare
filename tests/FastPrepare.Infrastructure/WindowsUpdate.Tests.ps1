<#
    Windows Update : la logique est testée avec une fausse session COM (aucun appel au vrai service).
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core, Infrastructure
    $m = @{ ModuleName = 'FastPrepare.Infrastructure' }

    function New-FakeUpdate([string]$Title, [switch]$Interactive, [bool]$Downloaded = $true, [int]$Code = 2) {
        $update = [pscustomobject]@{
            Title                = $Title
            InstallationBehavior = [pscustomobject]@{ CanRequestUserInput = [bool]$Interactive }
            EulaAccepted         = $false
            IsDownloaded         = $Downloaded
            ResultCode           = $Code
        }
        $update | Add-Member -MemberType ScriptMethod -Name AcceptEula -Value { $this.EulaAccepted = $true }
        return $update
    }

    function New-FakeSession([object[]]$Updates, [object[]]$Remaining = @(), [bool]$Reboot = $false) {
        $state = [pscustomobject]@{ Searches = 0; First = @($Updates); Remaining = @($Remaining); Reboot = $Reboot; Installed = $null }
        $session = [pscustomobject]@{ ClientApplicationID = ''; State = $state }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
            $searcher = [pscustomobject]@{ State = $this.State }
            $searcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
                param($criteria)
                $this.State.Searches++
                $list = if ($this.State.Searches -eq 1) { $this.State.First } else { $this.State.Remaining }
                [pscustomobject]@{ Updates = $list }
            }
            $searcher
        }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateDownloader -Value {
            $downloader = [pscustomobject]@{ Updates = $null }
            $downloader | Add-Member -MemberType ScriptMethod -Name Download -Value { [pscustomobject]@{ ResultCode = 2 } }
            $downloader
        }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateInstaller -Value {
            $installer = [pscustomobject]@{ Updates = $null; State = $this.State; ForceQuiet = $false; AllowSourcePrompts = $true }
            $this.State | Add-Member -NotePropertyName Installer -NotePropertyValue $installer -Force
            $installer | Add-Member -MemberType ScriptMethod -Name Install -Value {
                $updates = @($this.Updates)
                $this.State.Installed = $updates
                $installation = [pscustomobject]@{ RebootRequired = $this.State.Reboot; Updates = $updates }
                $installation | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value { param($i) [pscustomobject]@{ ResultCode = $this.Updates[$i].ResultCode } }
                $installation
            }
            $installer
        }
        return $session
    }
}

Describe 'Invoke-WindowsUpdatePass (fausse session)' {
    BeforeEach {
        Mock @m New-UpdateCollection { Write-Output -NoEnumerate ([System.Collections.ArrayList]::new()) }
    }

    It 'aucune mise à jour : rien à faire' {
        $result = Invoke-WindowsUpdatePass -Session (New-FakeSession -Updates @())
        $result.Found | Should -Be 0
        $result.Installed | Should -Be 0
    }

    It 'télécharge et installe, accepte les contrats, signale le redémarrage' {
        $updates = @((New-FakeUpdate 'KB1'), (New-FakeUpdate 'KB2'))
        $session = New-FakeSession -Updates $updates -Reboot $true
        $result = Invoke-WindowsUpdatePass -Session $session
        $result.Found | Should -Be 2
        $result.Installed | Should -Be 2
        $result.RebootRequired | Should -BeTrue
        @($updates | Where-Object { -not $_.EulaAccepted }).Count | Should -Be 0
        $session.ClientApplicationID | Should -Be 'FastPrepare'
    }

    It 'pilote déclaré « peut demander une saisie » : installé quand même, en mode silencieux forcé (constat sur poste réel)' {
        $session = New-FakeSession -Updates @((New-FakeUpdate 'Pilote écran' -Interactive), (New-FakeUpdate 'KB3'))
        $result = Invoke-WindowsUpdatePass -Session $session
        @($session.State.Installed).Title | Should -Be @('Pilote écran', 'KB3')
        $result.Installed | Should -Be 2
        $session.State.Installer.ForceQuiet | Should -BeTrue
        $session.State.Installer.AllowSourcePrompts | Should -BeFalse
    }

    It 'échecs de téléchargement et d''installation : titres relevés' {
        $session = New-FakeSession -Updates @((New-FakeUpdate 'Pas téléchargée' -Downloaded $false), (New-FakeUpdate 'En échec' -Code 4), (New-FakeUpdate 'OK avec erreurs' -Code 3))
        $result = Invoke-WindowsUpdatePass -Session $session
        @($result.Failed) | Should -Be @('Pas téléchargée', 'En échec')
        $result.Installed | Should -Be 1
    }

    It 'mises à jour encore disponibles après la passe : comptées (une seule passe, QO3)' {
        $session = New-FakeSession -Updates @((New-FakeUpdate 'KB4')) -Remaining @((New-FakeUpdate 'KB5'), (New-FakeUpdate 'KB6'))
        (Invoke-WindowsUpdatePass -Session $session).Remaining | Should -Be 2
        $session.State.Searches | Should -Be 2
    }
}

Describe 'Copie du journal sur la clé (E7)' {
    It 'sans repli : rien à copier' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'cle1') -FallbackFolder (Join-Path $TestDrive 'temp1') -HostName 'PC' -Stamp 's'
        @((Copy-RunLogToDrive -Log $log).Copied).Count | Should -Be 0
    }
    It 'clé redevenue accessible : journal et inventaire recopiés' {
        $blocked = Join-Path $TestDrive 'cle2'
        Set-Content -LiteralPath $blocked -Value 'un fichier à la place du dossier : écriture impossible'
        $log = New-RunLog -Folder $blocked -FallbackFolder (Join-Path $TestDrive 'temp2') -HostName 'PC' -Stamp 's'
        $log.IsFallback | Should -BeTrue
        Write-RunLog -Log $log -Message 'ligne'
        $inventory = Join-Path $log.Folder 'Inventaire_SN0000TEST_s.txt'
        Set-Content -LiteralPath $inventory -Value 'N/S'
        Remove-Item -LiteralPath $blocked   # la clé redevient accessible

        $copy = Copy-RunLogToDrive -Log $log -AdditionalFile @($inventory, $null)
        $copy.Error | Should -BeNullOrEmpty
        @($copy.Copied).Count | Should -Be 2
        (Join-Path $blocked 'Journal_PC_s.log') | Should -Exist
        (Join-Path $blocked 'Inventaire_SN0000TEST_s.txt') | Should -Exist
    }
    It 'clé toujours inaccessible : erreur rapportée, pas d''exception' {
        $blocked = Join-Path $TestDrive 'cle3'
        Set-Content -LiteralPath $blocked -Value 'x'
        $log = New-RunLog -Folder $blocked -FallbackFolder (Join-Path $TestDrive 'temp3') -HostName 'PC' -Stamp 's'
        (Copy-RunLogToDrive -Log $log).Error | Should -Match 'lecture seule'
    }
    It 'avancement publié pour la fenêtre, jamais écrit dans le fichier' {
        $log = New-RunLog -Folder (Join-Path $TestDrive 'cle4') -FallbackFolder (Join-Path $TestDrive 'temp4') -HostName 'PC' -Stamp 's'
        Publish-RunProgress -Log $log -Current 2 -Total 5 -Label 'action'
        $entry = @(Receive-RunLogEntry -Log $log)[0]
        $entry.Level | Should -Be 'PROGRESS'
        $entry.Current | Should -Be 2
        $log.FilePath | Should -Not -Exist
    }
}
