BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $catalog = @(Get-TestCatalogEntry)
}

Describe 'Outil du constructeur détecté seulement (DEC25)' {
    It '<Manufacturer> → <Expected>' -ForEach @(
        @{ Manufacturer = 'Dell Inc.'; Expected = 'dell-command-update' }
        @{ Manufacturer = 'HP'; Expected = 'hp-image-assistant' }
        @{ Manufacturer = 'Hewlett-Packard'; Expected = 'hp-image-assistant' }
        @{ Manufacturer = 'LENOVO'; Expected = 'lenovo-commercial-vantage,lenovo-thin-installer,lenovo-outil-direct' }
        @{ Manufacturer = 'FUJITSU CLIENT COMPUTING LIMITED'; Expected = 'fujitsu-deskupdate' }
    ) {
        $applicable = @(Select-ApplicableSoftware -Catalog $catalog -Manufacturer $Manufacturer)
        (@($applicable | Where-Object { $_.ManufacturerPattern } | ForEach-Object Id) -join ',') | Should -Be $Expected
        # Les entrées sans constructeur restent proposées partout.
        @($applicable | ForEach-Object Id) | Should -Contain 'adobe-reader'
    }
    It 'constructeur inconnu, vide ou non détecté : aucun outil constructeur, les autres logiciels restent' -ForEach @(
        @{ Manufacturer = 'Microsoft Corporation' }
        @{ Manufacturer = '' }
        @{ Manufacturer = '   ' }
        @{ Manufacturer = $null }
    ) {
        @(Select-ApplicableSoftware -Catalog $catalog -Manufacturer $Manufacturer | ForEach-Object Id) | Should -Be @('adobe-reader')
    }
    It 'ordre du catalogue conservé' {
        $ids = @(Select-ApplicableSoftware -Catalog $catalog -Manufacturer 'Dell Inc.' | ForEach-Object Id)
        $ids | Should -Be @('dell-command-update', 'adobe-reader')
    }
    It 'Test-SoftwareApplicable : insensible à la casse' {
        $dell = $catalog | Where-Object Id -EQ 'dell-command-update'
        Test-SoftwareApplicable -Entry $dell -Manufacturer 'DELL INC.' | Should -BeTrue
        Test-SoftwareApplicable -Entry $dell -Manufacturer 'HP' | Should -BeFalse
    }
    It 'catalogue vide : rien' {
        @(Select-ApplicableSoftware -Catalog @() -Manufacturer 'Dell Inc.').Count | Should -Be 0
    }
}

Describe 'Inventaire (section 10)' {
    It 'bloc aligné N/S puis une ligne MAC par carte' {
        $adapters = @([pscustomobject]@{ Name = 'Ethernet'; Mac = '00-11-22-33-44-55' }, [pscustomobject]@{ Name = 'Wi-Fi'; Mac = '66-77-88-99-AA-BB' })
        $lines = (Format-InventoryText -Serial 'SN0000TEST' -Adapter $adapters) -split "`r`n"
        $lines[0] | Should -Be ('{0,-22} {1}' -f 'N/S', 'SN0000TEST')
        $lines[2] | Should -Be ('{0,-22} {1}' -f 'MAC Wi-Fi', '66-77-88-99-AA-BB')
    }
    It 'export : en-tête puis bloc' {
        $identity = [pscustomobject]@{ HostName = 'PC1'; Manufacturer = 'LENOVO'; Model = '20NR' }
        $content = Format-InventoryExport -Identity $identity -InventoryText 'BLOC' -Date ([datetime]'2026-11-10 10:47')
        $content[0] | Should -Be 'Date         : 10/11/2026 10:47'
        $content[-1] | Should -Be 'BLOC'
    }
    It 'nom de fichier sûr : <Value> → <Expected>' -ForEach @(
        @{ Value = 'SN0000TEST'; Expected = 'SN0000TEST' }
        @{ Value = 'AB C/D'; Expected = 'AB_C_D' }
        @{ Value = ''; Expected = 'INCONNU' }
        @{ Value = '   '; Expected = 'INCONNU' }
    ) {
        ConvertTo-SafeFileName -Value $Value | Should -Be $Expected
    }
}

Describe 'New-Selection' {
    It 'rien n''est coché par défaut' {
        $s = New-Selection
        $s.HostName.Enabled | Should -BeFalse
        $s.VendorUtility.Key | Should -BeNullOrEmpty
        $s.Office.EditionKey | Should -BeNullOrEmpty
        @($s.Software.Items).Count | Should -Be 0
        $s.MicrosoftApps.OneDrive | Should -BeFalse
    }
}
