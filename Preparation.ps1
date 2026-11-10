#Requires -Version 5.1
<#
    Outil de préparation de poste — Étape 1 : interface + détections, bouton Lancer en simulation.
    Lancement : Lancer.cmd (droits administrateur, Windows PowerShell 5.1).
    Aucune modification du poste dans cette version, hormis l'écriture du journal
    et de l'inventaire (N/S, MAC) dans le dossier logs\ à côté du script.
#>

$script:Simulation = $true
$script:Root = $PSScriptRoot
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Net.Http

# ---------------------------------------------------------------- Droits administrateur
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.MessageBox]::Show("Cet outil doit être lancé en administrateur.`nUtilisez Lancer.cmd.", 'Préparation de poste', 'OK', 'Warning') | Out-Null
    exit 1
}

# ---------------------------------------------------------------- Configuration et journal
$configPath = Join-Path $script:Root 'config.json'
try {
    $script:Config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    [System.Windows.MessageBox]::Show("config.json introuvable ou invalide :`n$configPath`n`n$($_.Exception.Message)", 'Préparation de poste', 'OK', 'Error') | Out-Null
    exit 1
}

$script:LogDir = Join-Path $script:Root 'logs'
try {
    if (-not (Test-Path -LiteralPath $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -ErrorAction Stop | Out-Null }
    $probe = Join-Path $script:LogDir '.ecriture'
    Set-Content -LiteralPath $probe -Value 'ok' -ErrorAction Stop
    Remove-Item -LiteralPath $probe -ErrorAction SilentlyContinue
} catch {
    # Clé en lecture seule : repli sur le dossier temporaire
    $script:LogDir = Join-Path $env:TEMP 'PreparationPoste'
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile = Join-Path $script:LogDir ("Journal_{0}_{1}.log" -f $env:COMPUTERNAME, $stamp)

# ---------------------------------------------------------------- Interface (XAML)
$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Préparation de poste" Width="1240" Height="880" MinWidth="1020" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Segoe UI" FontSize="13" Foreground="#1B1B1B">
  <Window.Resources>
    <Style x:Key="Section" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#E0E0E0"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="16,14"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
    </Style>
    <Style x:Key="H2" TargetType="TextBlock">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#5D5D5D"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Foreground" Value="#5D5D5D"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Tech" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Foreground" Value="#5D5D5D"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="22,0,0,6"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Margin" Value="0,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Card" TargetType="ToggleButton">
      <Setter Property="Padding" Value="8,10"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="bd" Background="White" BorderBrush="#D6D6D6" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#005FB8"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E5F0FB"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#005FB8"/>
                <Setter TargetName="bd" Property="BorderThickness" Value="2"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Pill" TargetType="ToggleButton">
      <Setter Property="Padding" Value="12,4"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="bd" Background="White" BorderBrush="#D6D6D6" BorderThickness="1" CornerRadius="12" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E5F0FB"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#005FB8"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="#005FB8" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#004A8F"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#C8C8C8"/>
                <Setter Property="Foreground" Value="#6E6E6E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <DockPanel>
    <!-- En-tête : connexion internet + poste détecté -->
    <Border DockPanel.Dock="Top" Background="White" BorderBrush="#E0E0E0" BorderThickness="0,0,0,1" Padding="20,10">
      <DockPanel>
        <Border Name="BdSimu" DockPanel.Dock="Right" Background="#FFF4CE" CornerRadius="4" Padding="10,4" VerticalAlignment="Center">
          <TextBlock Text="MODE SIMULATION — aucune modification du poste" Foreground="#8A5A00" FontWeight="SemiBold" FontSize="12"/>
        </Border>
        <StackPanel Orientation="Horizontal">
          <Border Name="BdNet" CornerRadius="14" Padding="12,6" Background="#FDE7E9" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <Ellipse Name="NetDot" Width="10" Height="10" Fill="#C42B1C" VerticalAlignment="Center"/>
              <TextBlock Name="TxtNet" Margin="8,0,0,0" FontWeight="SemiBold" Foreground="#A4262C" Text="Test de la connexion…"/>
            </StackPanel>
          </Border>
          <TextBlock Name="TxtPoste" Margin="24,0,0,0" VerticalAlignment="Center" Foreground="#5D5D5D"/>
          <TextBlock Name="TxtOs" Margin="24,0,0,0" VerticalAlignment="Center" Foreground="#5D5D5D"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- Pied : journal + bouton Lancer -->
    <Border DockPanel.Dock="Bottom" Background="White" BorderBrush="#E0E0E0" BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="236"/>
        </Grid.ColumnDefinitions>
        <RichTextBox Name="RtbLog" Height="130" IsReadOnly="True" Background="#1E1E1E" Foreground="#D4D4D4"
                     FontFamily="Consolas" FontSize="12" BorderThickness="0" Padding="6" VerticalScrollBarVisibility="Auto"/>
        <StackPanel Grid.Column="1" Margin="16,0,0,0" VerticalAlignment="Center">
          <Button Name="BtnGo" Content="Lancer" Height="44" FontSize="15" FontWeight="SemiBold" IsEnabled="False" Style="{StaticResource Primary}"/>
          <TextBlock Name="TxtGoHint" Style="{StaticResource Hint}" TextAlignment="Center" Margin="0,6,0,0" Text="Grisé : connexion internet non validée"/>
        </StackPanel>
      </Grid>
    </Border>

    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <Grid Margin="20,16,20,4">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="16"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- ================= Colonne gauche ================= -->
        <StackPanel Grid.Column="0">

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="1 · Changer le nom d'hôte"/>
              <DockPanel>
                <CheckBox Name="ChkHost" DockPanel.Dock="Left" Content="Renommer l'hôte" Margin="0,0,12,0" VerticalAlignment="Center"/>
                <TextBox Name="TxtHost" Height="30" Padding="8,0" VerticalContentAlignment="Center" MaxLength="15" IsEnabled="False"/>
              </DockPanel>
              <TextBlock Name="TxtHostHint" Style="{StaticResource Hint}" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <DockPanel>
                <CheckBox Name="ChkAllApps" DockPanel.Dock="Right" Content="Tout cocher" FontSize="12" Foreground="#5D5D5D"/>
                <TextBlock Style="{StaticResource H2}" Text="2 · Désinstallation des logiciels installés"/>
              </DockPanel>
              <Border BorderBrush="#E5E5E5" BorderThickness="1" CornerRadius="4">
                <StackPanel>
                  <Grid Background="#F7F7F7">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="170"/>
                      <ColumnDefinition Width="96"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Nom" Margin="32,6,8,6" FontSize="11.5" FontWeight="SemiBold" Foreground="#5D5D5D"/>
                    <TextBlock Grid.Column="1" Text="Éditeur" Margin="0,6,8,6" FontSize="11.5" FontWeight="SemiBold" Foreground="#5D5D5D"/>
                    <TextBlock Grid.Column="2" Text="Silencieux" Margin="0,6,8,6" FontSize="11.5" FontWeight="SemiBold" Foreground="#5D5D5D"/>
                  </Grid>
                  <ScrollViewer MaxHeight="250" VerticalScrollBarVisibility="Auto">
                    <StackPanel Name="PnlApps"/>
                  </ScrollViewer>
                </StackPanel>
              </Border>
              <TextBlock Style="{StaticResource Hint}" Foreground="#8A5A00" Margin="0,8,0,0"
                         Text="⚠ = désinstallation silencieuse indisponible : l'assistant de l'application s'ouvrira, traité en dernier"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="3 · Désinstallation des programmes Microsoft"/>
              <CheckBox Name="ChkOfficeC2R" IsChecked="True" Content="Office Click-to-Run — toutes éditions et langues"/>
              <TextBlock Style="{StaticResource Tech}" Text="ODT /configure → &lt;Remove All=&quot;TRUE&quot;/&gt;"/>
              <CheckBox Name="ChkOfficeMsi" IsChecked="True" Content="Office MSI — 2010, 2013, 2016"/>
              <TextBlock Style="{StaticResource Tech}" Text="ODT /configure → &lt;RemoveMSI/&gt;"/>
              <CheckBox Name="ChkOutlookClassic" IsChecked="True" Content="Outlook classique"/>
              <TextBlock Style="{StaticResource Tech}" Text="composant C2R / MSI → retiré avec la suite Office"/>
              <CheckBox Name="ChkOutlookNew" IsChecked="True" Content="Nouvel Outlook"/>
              <TextBlock Style="{StaticResource Tech}" Text="Appx Microsoft.OutlookForWindows → Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage"/>
              <CheckBox Name="ChkOneNote" IsChecked="True" Content="OneNote"/>
              <TextBlock Style="{StaticResource Tech}" Text="OneNote C2R (Remove All) + Appx Microsoft.Office.OneNote"/>
              <CheckBox Name="ChkTeams" IsChecked="True" Content="Teams — classique, nouveau, personnel"/>
              <TextBlock Style="{StaticResource Tech}" Text="MSI Teams Machine-Wide Installer + %LocalAppData%\Microsoft\Teams · Appx MSTeams · Appx MicrosoftTeams"/>
              <Border BorderBrush="#EFEFEF" BorderThickness="0,1,0,0" Margin="0,4,0,0" Padding="0,8,0,0">
                <StackPanel>
                  <CheckBox Name="ChkOneDrive" IsChecked="True" Content="OneDrive"/>
                  <TextBlock Style="{StaticResource Tech}" Text="OneDriveSetup.exe /uninstall (+ /allusers) · clé Run OneDriveSetup retirée du profil Default"/>
                  <StackPanel Orientation="Horizontal" Margin="22,0,0,0">
                    <CheckBox Name="ChkOneDriveFolder" Content="Dossier OneDrive"/>
                    <Border Background="#FFF4CE" CornerRadius="9" Padding="8,1" Margin="10,0,0,0" VerticalAlignment="Center">
                      <TextBlock Name="TxtOneDriveCount" FontSize="11.5" Foreground="#8A5A00"/>
                    </Border>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Tech}" Margin="44,0,0,0" Text="Remove-Item %UserProfile%\OneDrive -Recurse"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="4 · Suppression des sessions locales"/>
              <StackPanel Name="PnlUsers"/>
              <TextBlock Name="TxtUsersNone" Style="{StaticResource Hint}" Text="Aucune autre session locale à supprimer." Visibility="Collapsed"/>
              <TextBlock Name="TxtUsersExcluded" Style="{StaticResource Hint}" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>

        </StackPanel>

        <!-- ================= Colonne droite ================= -->
        <StackPanel Grid.Column="2">

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="5 · Installation d'utilitaire constructeur"/>
              <UniformGrid Columns="4">
                <ToggleButton Name="CardDell" Tag="dell" Style="{StaticResource Card}">
                  <StackPanel>
                    <Image Name="ImgDell" Height="40" Margin="0,0,0,6" Visibility="Collapsed"/>
                    <TextBlock Text="Dell" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                    <TextBlock Text="Command Update" Style="{StaticResource Hint}" TextAlignment="Center"/>
                  </StackPanel>
                </ToggleButton>
                <ToggleButton Name="CardHp" Tag="hp" Style="{StaticResource Card}">
                  <StackPanel>
                    <Image Name="ImgHp" Height="40" Margin="0,0,0,6" Visibility="Collapsed"/>
                    <TextBlock Text="HP" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                    <TextBlock Text="Image Assistant" Style="{StaticResource Hint}" TextAlignment="Center"/>
                  </StackPanel>
                </ToggleButton>
                <ToggleButton Name="CardLenovo" Tag="lenovo" Style="{StaticResource Card}">
                  <StackPanel>
                    <Image Name="ImgLenovo" Height="40" Margin="0,0,0,6" Visibility="Collapsed"/>
                    <TextBlock Text="Lenovo" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                    <TextBlock Text="Commercial Vantage + Thin Installer" Style="{StaticResource Hint}" TextAlignment="Center"/>
                  </StackPanel>
                </ToggleButton>
                <ToggleButton Name="CardFujitsu" Tag="fujitsu" Style="{StaticResource Card}" Margin="0">
                  <StackPanel>
                    <Image Name="ImgFujitsu" Height="40" Margin="0,0,0,6" Visibility="Collapsed"/>
                    <TextBlock Text="Fujitsu" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                    <TextBlock Text="DeskUpdate" Style="{StaticResource Hint}" TextAlignment="Center"/>
                  </StackPanel>
                </ToggleButton>
              </UniformGrid>
              <TextBlock Name="TxtUtilStatus" Style="{StaticResource Hint}" Margin="0,8,0,0" Text="Aucun utilitaire sélectionné. Cliquer à nouveau sur une card la désélectionne."/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="6 · Installation Office 365 — Méthode ODT"/>
              <UniformGrid Columns="4">
                <ToggleButton Name="CardO365" Tag="O365" Style="{StaticResource Card}">
                  <TextBlock Text="365 Apps for Business" FontWeight="SemiBold" TextWrapping="Wrap" TextAlignment="Center"/>
                </ToggleButton>
                <ToggleButton Name="CardLtsc2024" Tag="LTSC2024" Style="{StaticResource Card}">
                  <TextBlock Text="LTSC Pro Plus 2024" FontWeight="SemiBold" TextWrapping="Wrap" TextAlignment="Center"/>
                </ToggleButton>
                <ToggleButton Name="CardStd2019" Tag="STD2019" Style="{StaticResource Card}">
                  <TextBlock Text="Standard 2019" FontWeight="SemiBold" TextWrapping="Wrap" TextAlignment="Center"/>
                </ToggleButton>
                <ToggleButton Name="CardPp2019" Tag="PP2019" Style="{StaticResource Card}" Margin="0">
                  <TextBlock Text="Pro Plus 2019" FontWeight="SemiBold" TextWrapping="Wrap" TextAlignment="Center"/>
                </ToggleButton>
              </UniformGrid>
              <StackPanel Name="PnlLicence" Orientation="Horizontal" Margin="0,10,0,0" Visibility="Collapsed">
                <TextBlock Text="Licence :" FontSize="12" Foreground="#5D5D5D" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <ToggleButton Name="PillTeams" Style="{StaticResource Pill}" Content="Avec Teams" IsChecked="True"/>
                <ToggleButton Name="PillNoTeams" Style="{StaticResource Pill}" Content="Sans Teams (EEE)"/>
              </StackPanel>
              <StackPanel Name="PnlInclude" Orientation="Horizontal" Margin="0,10,0,0" IsEnabled="False">
                <TextBlock Text="Inclure :" FontSize="12" Foreground="#5D5D5D" VerticalAlignment="Center" Margin="0,0,16,0"/>
                <CheckBox Name="ChkIncNewOutlook" Content="Nouvel Outlook" IsChecked="True" Margin="0,3,20,3"/>
                <CheckBox Name="ChkIncClassicOutlook" Content="Outlook classique" IsChecked="True" Margin="0,3,20,3"/>
                <CheckBox Name="ChkIncOneDrive" Content="OneDrive" IsChecked="True"/>
              </StackPanel>
              <TextBlock Name="TxtOfficeInfo" Style="{StaticResource Hint}" Margin="0,8,0,0" Text="Aucune édition sélectionnée : Office ne sera pas installé."/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="7 · MàJ"/>
              <CheckBox Name="ChkWU" IsChecked="True" Content="Lancer Windows Update"/>
              <CheckBox Name="ChkUtilUpdate" IsEnabled="False" Content="Lancer la MàJ de l'utilitaire constructeur (pilotes, BIOS)"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="8 · Installation logiciels"/>
              <CheckBox Name="ChkAdobe" IsChecked="True" Content="Adobe Acrobat Reader (64 bits)"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <TextBlock Style="{StaticResource H2}" Text="9 · Configuration des paramètres système"/>
              <TextBlock Style="{StaticResource Sub}" Text="Désactivation IPv6 (interfaces NIC)"/>
              <StackPanel Name="PnlNics"/>
              <Border BorderBrush="#EFEFEF" BorderThickness="0,1,0,0" Margin="0,8,0,0" Padding="0,8,0,0">
                <StackPanel>
                  <TextBlock Style="{StaticResource Sub}" Text="Mode d'alimentation"/>
                  <CheckBox Name="ChkPower" IsChecked="True" Content="Éteindre l'écran après 5 min · Mise en veille après 15 min (secteur et batterie)"/>
                  <TextBlock Style="{StaticResource Tech}" Text="powercfg /change monitor-timeout-ac|dc 5 · standby-timeout-ac|dc 15"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Section}">
            <StackPanel>
              <DockPanel>
                <Button Name="BtnCopy" DockPanel.Dock="Right" Content="Copier" Padding="12,3" VerticalAlignment="Top"/>
                <TextBlock Style="{StaticResource H2}" Text="10 · Numéro de série et adresses MAC"/>
              </DockPanel>
              <TextBox Name="TxtInventory" IsReadOnly="True" BorderThickness="0" Background="Transparent" FontFamily="Consolas" FontSize="12.5" TextWrapping="NoWrap"/>
              <TextBlock Name="TxtExport" Style="{StaticResource Hint}" Margin="0,8,0,0"/>
            </StackPanel>
          </Border>

        </StackPanel>

        <!-- ================= Mémo ================= -->
        <Border Grid.Row="1" Grid.ColumnSpan="3" Background="#FFF8D6" BorderBrush="#E8C84A" BorderThickness="1" CornerRadius="6" Padding="18,12" Margin="0,0,0,12">
          <TextBlock TextWrapping="Wrap" Foreground="#3D3200" FontSize="12.5">
            <Run FontWeight="SemiBold" Text="Mémo — fait à la main, hors outil : "/>
            <Run Text="réinitialisation de Windows (avant) · installation du RMM · installation de l'antivirus · chiffrement BitLocker · activation d'Office · redémarrage final"/>
          </TextBlock>
        </Border>
      </Grid>
    </ScrollViewer>
  </DockPanel>
</Window>
'@

$xamlDoc = [xml]$Xaml
$reader  = New-Object System.Xml.XmlNodeReader $xamlDoc
$Window  = [Windows.Markup.XamlReader]::Load($reader)

# Table des contrôles nommés : $UI.NomDuControle
$UI = @{}
foreach ($node in $xamlDoc.SelectNodes('//*[@Name]')) {
    $name = $node.GetAttribute('Name')
    $element = $Window.FindName($name)
    if ($element) { $UI[$name] = $element }
}

# ---------------------------------------------------------------- Outils d'interface
function Get-Brush {
    param([string]$Hex)
    return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex)
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'ERREUR', 'ATTN', 'SIMU')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }

    $color = switch ($Level) {
        'OK'     { '#6A9955' }
        'ERREUR' { '#F48771' }
        'ATTN'   { '#DCDCAA' }
        'SIMU'   { '#569CD6' }
        default  { '#D4D4D4' }
    }
    $paragraph = New-Object System.Windows.Documents.Paragraph
    $paragraph.Margin = New-Object System.Windows.Thickness(0)
    $run = New-Object System.Windows.Documents.Run($line)
    $run.Foreground = Get-Brush $color
    $paragraph.Inlines.Add($run)
    $UI.RtbLog.Document.Blocks.Add($paragraph)
    $UI.RtbLog.ScrollToEnd()
}

function New-GridColumn {
    param($Grid, [double]$Value, [switch]$Star)
    $column = New-Object System.Windows.Controls.ColumnDefinition
    if ($Star) {
        $column.Width = New-Object System.Windows.GridLength($Value, [System.Windows.GridUnitType]::Star)
    } else {
        $column.Width = New-Object System.Windows.GridLength($Value)
    }
    $Grid.ColumnDefinitions.Add($column)
}

# ---------------------------------------------------------------- Détections
function Test-NsisUninstaller {
    param([string]$Path)
    try {
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.Length -gt 10MB) { return $false }
        $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($Path))
        return ($text.IndexOf('Nullsoft', [System.StringComparison]::Ordinal) -ge 0)
    } catch { return $false }
}

function Get-UninstallPlan {
    # Détermine la commande de désinstallation et si elle est silencieuse.
    param($Entry)
    if ($Entry.QuietUninstallString) {
        return @{ Silent = $true; Method = 'QuietUninstallString'; Command = [string]$Entry.QuietUninstallString }
    }
    $uninstall = [string]$Entry.UninstallString
    if ($Entry.WindowsInstaller -eq 1 -or $uninstall -match '(?i)msiexec') {
        $guid = $null
        if ($Entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $guid = $Entry.PSChildName }
        elseif ($uninstall -match '\{[0-9A-Fa-f-]{36}\}') { $guid = $Matches[0] }
        if ($guid) {
            return @{ Silent = $true; Method = 'MSI'; Command = "msiexec.exe /x $guid /qn /norestart" }
        }
    }
    if (-not $uninstall) {
        return @{ Silent = $false; Method = 'Aucune commande'; Command = $null }
    }
    $exe = $null
    if ($uninstall -match '^\s*"([^"]+)"') { $exe = $Matches[1] }
    elseif ($uninstall -match '(?i)^\s*(.+?\.exe)') { $exe = $Matches[1] }
    if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
        $leaf = Split-Path -Path $exe -Leaf
        if ($leaf -match '(?i)^unins\d{3}\.exe$') {
            return @{ Silent = $true; Method = 'Inno Setup'; Command = "`"$exe`" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" }
        }
        if (Test-NsisUninstaller -Path $exe) {
            return @{ Silent = $true; Method = 'NSIS'; Command = "`"$exe`" /S" }
        }
    }
    return @{ Silent = $false; Method = 'Assistant'; Command = $uninstall }
}

function Get-InstalledSoftware {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seen = @{}
    $result = foreach ($entry in (Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)) {
        if (-not $entry.DisplayName) { continue }
        if ($entry.SystemComponent -eq 1) { continue }
        if ($entry.ParentKeyName -or $entry.ParentDisplayName) { continue }
        if ($entry.ReleaseType -match 'Update|Hotfix') { continue }
        $key = '{0}|{1}' -f $entry.DisplayName, $entry.DisplayVersion
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $plan = Get-UninstallPlan -Entry $entry
        [pscustomobject]@{
            Name      = [string]$entry.DisplayName
            Version   = [string]$entry.DisplayVersion
            Publisher = [string]$entry.Publisher
            Silent    = $plan.Silent
            Method    = $plan.Method
            Command   = $plan.Command
        }
    }
    return @($result | Sort-Object Name)
}

function Get-RemovableLocalUsers {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $profiles = @{}
    foreach ($p in (Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue)) { $profiles[$p.SID] = $p.LocalPath }
    $accounts = @()
    try {
        $accounts = Get-LocalUser -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ Name = $_.Name; SID = $_.SID.Value } }
    } catch {
        $accounts = Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; SID = $_.SID } }
    }
    $removable = @()
    $excluded = @()
    foreach ($a in $accounts) {
        if ($a.SID -eq $currentSid) { $excluded += "$($a.Name) (connecté)"; continue }
        if ($a.SID -match '-(500|501|503|504)$') { $excluded += $a.Name; continue }
        $removable += [pscustomobject]@{ Name = $a.Name; SID = $a.SID; ProfilePath = $profiles[$a.SID] }
    }
    return @{ Removable = $removable; Excluded = $excluded }
}

function Get-PhysicalAdapters {
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($adapter in $adapters) {
        $binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name        = $adapter.Name
            Description = $adapter.InterfaceDescription
            Mac         = $adapter.MacAddress
            Ipv6Enabled = [bool]($binding -and $binding.Enabled)
        }
    }
}

# ---------------------------------------------------------------- Remplissage des listes
$script:AppChecks  = New-Object System.Collections.ArrayList
$script:UserChecks = New-Object System.Collections.ArrayList
$script:NicChecks  = New-Object System.Collections.ArrayList

function Add-AppRow {
    param($App)
    $grid = New-Object System.Windows.Controls.Grid
    New-GridColumn -Grid $grid -Value 1 -Star
    New-GridColumn -Grid $grid -Value 170
    New-GridColumn -Grid $grid -Value 96

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $App.Name
    $label.TextTrimming = 'CharacterEllipsis'
    $check = New-Object System.Windows.Controls.CheckBox
    $check.Content = $label
    $check.Tag = $App
    $check.Margin = New-Object System.Windows.Thickness(10, 5, 8, 5)
    $check.ToolTip = if ($App.Command) { "$($App.Method) : $($App.Command)" } else { $App.Method }
    [System.Windows.Controls.Grid]::SetColumn($check, 0)

    $publisher = New-Object System.Windows.Controls.TextBlock
    $publisher.Text = $App.Publisher
    $publisher.Foreground = Get-Brush '#5D5D5D'
    $publisher.TextTrimming = 'CharacterEllipsis'
    $publisher.VerticalAlignment = 'Center'
    $publisher.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    [System.Windows.Controls.Grid]::SetColumn($publisher, 1)

    $mark = New-Object System.Windows.Controls.TextBlock
    $mark.FontWeight = 'SemiBold'
    $mark.VerticalAlignment = 'Center'
    if ($App.Silent) { $mark.Text = '✓ Oui'; $mark.Foreground = Get-Brush '#0F7B0F' }
    else { $mark.Text = '⚠ Non'; $mark.Foreground = Get-Brush '#8A5A00' }
    [System.Windows.Controls.Grid]::SetColumn($mark, 2)

    [void]$grid.Children.Add($check)
    [void]$grid.Children.Add($publisher)
    [void]$grid.Children.Add($mark)

    $border = New-Object System.Windows.Controls.Border
    $border.BorderBrush = Get-Brush '#EFEFEF'
    $border.BorderThickness = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $border.Child = $grid
    [void]$UI.PnlApps.Children.Add($border)
    [void]$script:AppChecks.Add($check)
}

function Initialize-Detections {
    # Poste
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $displayVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
    $script:Manufacturer = [string]$cs.Manufacturer
    $script:Model        = [string]$cs.Model
    $script:Serial       = [string]$bios.SerialNumber
    $UI.TxtPoste.Text = "Poste détecté : $($script:Manufacturer) — $($script:Model)"
    $UI.TxtOs.Text    = (("$($os.Caption) $displayVersion") -replace '^Microsoft\s+', '').Trim()
    $UI.TxtHostHint.Text = "Nom actuel : $env:COMPUTERNAME · 15 caractères max · lettres, chiffres, tiret · appliqué au redémarrage"
    Write-Log "Poste : $($script:Manufacturer) $($script:Model), N/S $($script:Serial)"

    # Winget
    if (Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue) { Write-Log 'Winget détecté' 'OK' }
    else { Write-Log 'Winget introuvable : il sera réenregistré avant les installations' 'ATTN' }

    # Logiciels
    $apps = @(Get-InstalledSoftware)
    foreach ($app in $apps) { Add-AppRow -App $app }
    $notSilent = @($apps | Where-Object { -not $_.Silent }).Count
    Write-Log "$($apps.Count) logiciels détectés, dont $notSilent sans désinstallation silencieuse"

    # Sessions locales
    $users = Get-RemovableLocalUsers
    foreach ($user in $users.Removable) {
        $check = New-Object System.Windows.Controls.CheckBox
        $profileText = if ($user.ProfilePath) { "compte + profil $($user.ProfilePath)" } else { 'compte (aucun profil sur le disque)' }
        $check.Content = "$($user.Name) — $profileText"
        $check.Tag = $user
        [void]$UI.PnlUsers.Children.Add($check)
        [void]$script:UserChecks.Add($check)
    }
    if ($users.Removable.Count -eq 0) { $UI.TxtUsersNone.Visibility = 'Visible' }
    $UI.TxtUsersExcluded.Text = "Exclus d'office : " + ($users.Excluded -join ' · ')

    # Cartes réseau
    $script:Adapters = @(Get-PhysicalAdapters)
    foreach ($nic in $script:Adapters) {
        $check = New-Object System.Windows.Controls.CheckBox
        $suffix = if ($nic.Ipv6Enabled) { '' } else { ' (IPv6 déjà désactivé)' }
        $check.Content = "$($nic.Name) — $($nic.Description)$suffix"
        $check.Tag = $nic
        $check.IsChecked = $nic.Ipv6Enabled
        [void]$UI.PnlNics.Children.Add($check)
        [void]$script:NicChecks.Add($check)
    }

    # Dossier OneDrive de la session en cours
    $script:OneDriveFolder = Join-Path $env:USERPROFILE 'OneDrive'
    if (Test-Path -LiteralPath $script:OneDriveFolder) {
        $count = @(Get-ChildItem -LiteralPath $script:OneDriveFolder -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        $UI.TxtOneDriveCount.Text = "$count fichier(s) trouvé(s)"
    } else {
        $UI.TxtOneDriveCount.Text = 'dossier absent'
    }

    # Inventaire N/S + MAC
    $lines = @('{0,-22} {1}' -f 'N/S', $script:Serial)
    foreach ($nic in $script:Adapters) { $lines += ('{0,-22} {1}' -f "MAC $($nic.Name)", $nic.Mac) }
    $script:InventoryText = $lines -join "`r`n"
    $UI.TxtInventory.Text = $script:InventoryText

    $safeSerial = ($script:Serial -replace '[^A-Za-z0-9_-]', '_')
    $exportFile = Join-Path $script:LogDir ("Inventaire_{0}_{1}.txt" -f $safeSerial, $stamp)
    $export = @(
        "Date         : $(Get-Date -Format 'dd/MM/yyyy HH:mm')",
        "Nom d'hôte   : $env:COMPUTERNAME",
        "Constructeur : $($script:Manufacturer)",
        "Modèle       : $($script:Model)",
        $script:InventoryText
    )
    try {
        Set-Content -LiteralPath $exportFile -Value $export -Encoding UTF8 -ErrorAction Stop
        $UI.TxtExport.Text = "Exporté dans $exportFile"
        Write-Log "Inventaire exporté : $exportFile" 'OK'
    } catch {
        $UI.TxtExport.Text = "Export impossible : $($_.Exception.Message)"
        Write-Log "Export de l'inventaire impossible : $($_.Exception.Message)" 'ERREUR'
    }

    # Logos des cards (logos\dell.png, hp.png, lenovo.png, fujitsu.png)
    foreach ($pair in @(@('dell', 'ImgDell'), @('hp', 'ImgHp'), @('lenovo', 'ImgLenovo'), @('fujitsu', 'ImgFujitsu'))) {
        $logo = Join-Path $script:Root ("logos\{0}.png" -f $pair[0])
        if (Test-Path -LiteralPath $logo) {
            try {
                $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
                $bitmap.BeginInit()
                $bitmap.CacheOption = 'OnLoad'
                $bitmap.UriSource = [Uri]$logo
                $bitmap.EndInit()
                $UI[$pair[1]].Source = $bitmap
                $UI[$pair[1]].Visibility = 'Visible'
            } catch { }
        }
    }

    # Présélection de l'utilitaire selon le constructeur
    $card = switch -Regex ($script:Manufacturer) {
        'Dell'               { $UI.CardDell; break }
        'HP|Hewlett'         { $UI.CardHp; break }
        'Lenovo'             { $UI.CardLenovo; break }
        'Fujitsu'            { $UI.CardFujitsu; break }
    }
    if ($card) { $card.IsChecked = $true }
}

# ---------------------------------------------------------------- États et règles d'interface
$script:NetOk = $false
$script:UtilCards   = @($UI.CardDell, $UI.CardHp, $UI.CardLenovo, $UI.CardFujitsu)
$script:OfficeCards = @($UI.CardO365, $UI.CardLtsc2024, $UI.CardStd2019, $UI.CardPp2019)

$script:OfficeEditions = @{
    O365     = @{ Name = 'Microsoft 365 Apps for Business'; ProductId = 'O365BusinessRetail'; Channel = 'MonthlyEnterprise' }
    LTSC2024 = @{ Name = 'Office LTSC Professional Plus 2024'; ProductId = 'ProPlus2024Volume'; Channel = 'PerpetualVL2024' }
    STD2019  = @{ Name = 'Office Standard 2019'; ProductId = 'Standard2019Volume'; Channel = 'PerpetualVL2019' }
    PP2019   = @{ Name = 'Office Professional Plus 2019'; ProductId = 'ProPlus2019Volume'; Channel = 'PerpetualVL2019' }
}

function Test-HostName {
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9]([A-Za-z0-9-]{0,13}[A-Za-z0-9])?$') -and ($Name -notmatch '^\d+$')
}

function Update-LaunchState {
    $hostOk = (-not $UI.ChkHost.IsChecked) -or (Test-HostName -Name $UI.TxtHost.Text)
    $UI.BtnGo.IsEnabled = $script:NetOk -and $hostOk
    if (-not $script:NetOk) { $UI.TxtGoHint.Text = 'Grisé : connexion internet non validée' }
    elseif (-not $hostOk)   { $UI.TxtGoHint.Text = "Grisé : nom d'hôte invalide" }
    elseif ($script:Simulation) { $UI.TxtGoHint.Text = 'Simulation : rien ne sera modifié' }
    else { $UI.TxtGoHint.Text = 'Aucun redémarrage automatique' }
}

function Update-HostState {
    $UI.TxtHost.IsEnabled = [bool]$UI.ChkHost.IsChecked
    if ($UI.ChkHost.IsChecked -and $UI.TxtHost.Text -and -not (Test-HostName -Name $UI.TxtHost.Text)) {
        $UI.TxtHostHint.Foreground = Get-Brush '#C42B1C'
    } else {
        $UI.TxtHostHint.Foreground = Get-Brush '#5D5D5D'
    }
    Update-LaunchState
}

function Get-SelectedKey {
    param($Cards)
    foreach ($card in $Cards) { if ($card.IsChecked) { return [string]$card.Tag } }
    return $null
}

function Update-UtilState {
    $key = Get-SelectedKey -Cards $script:UtilCards
    $UI.ChkUtilUpdate.IsEnabled = [bool]$key
    if ($key) {
        $util = $script:Config.Utilities.$key
        $UI.ChkUtilUpdate.IsChecked = $true
        $UI.TxtUtilStatus.Text = "$($util.Brand) $($util.Tool) · winget $($util.WingetId) (source $($util.WingetSource))"
    } else {
        $UI.ChkUtilUpdate.IsChecked = $false
        $UI.TxtUtilStatus.Text = 'Aucun utilitaire sélectionné. Cliquer à nouveau sur une card la désélectionne.'
    }
}

function Get-OfficePlan {
    $key = Get-SelectedKey -Cards $script:OfficeCards
    if (-not $key) { return $null }
    $edition = $script:OfficeEditions[$key]
    $productId = $edition.ProductId
    if ($key -eq 'O365' -and $UI.PillNoTeams.IsChecked) { $productId = 'O365BusinessEEANoTeamsRetail' }
    $exclude = @()
    if (-not $UI.ChkIncNewOutlook.IsChecked)     { $exclude += 'OutlookForWindows' }
    if (-not $UI.ChkIncClassicOutlook.IsChecked) { $exclude += 'Outlook' }
    if (-not $UI.ChkIncOneDrive.IsChecked)       { $exclude += 'OneDrive' }

    $xml = @('<Configuration>')
    $xml += '  <Add OfficeClientEdition="64" Channel="{0}">' -f $edition.Channel
    $xml += '    <Product ID="{0}">' -f $productId
    $xml += '      <Language ID="MatchOS" />'
    foreach ($app in $exclude) { $xml += '      <ExcludeApp ID="{0}" />' -f $app }
    $xml += '    </Product>'
    $xml += '  </Add>'
    $xml += '  <Updates Enabled="TRUE" />'
    $xml += '  <Display Level="None" AcceptEULA="TRUE" />'
    $xml += '  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />'
    $xml += '</Configuration>'
    return @{ Key = $key; Name = $edition.Name; ProductId = $productId; Exclude = $exclude; Xml = ($xml -join "`r`n") }
}

function Update-OfficeState {
    $plan = Get-OfficePlan
    $UI.PnlInclude.IsEnabled = [bool]$plan
    if (-not $plan) {
        $UI.PnlLicence.Visibility = 'Collapsed'
        $UI.TxtOfficeInfo.Text = 'Aucune édition sélectionnée : Office ne sera pas installé.'
        return
    }
    $UI.PnlLicence.Visibility = if ($plan.Key -eq 'O365') { 'Visible' } else { 'Collapsed' }
    $excludeText = if ($plan.Exclude.Count) { 'exclus : ' + ($plan.Exclude -join ', ') } else { 'aucune exclusion' }
    $UI.TxtOfficeInfo.Text = "XML généré à la volée dans $($script:Config.Office.OdtFolder) · ID produit $($plan.ProductId) · $excludeText · activation manuelle plus tard"
}

function Set-NetState {
    param([bool]$Ok)
    if ($Ok -ne $script:NetOk -or -not $script:NetKnown) {
        if ($Ok) { Write-Log 'Connexion internet validée' 'OK' } else { Write-Log 'Pas de connexion internet' 'ERREUR' }
    }
    $script:NetKnown = $true
    $script:NetOk = $Ok
    if ($Ok) {
        $UI.BdNet.Background = Get-Brush '#DFF6DD'; $UI.NetDot.Fill = Get-Brush '#0F7B0F'
        $UI.TxtNet.Foreground = Get-Brush '#0F5A0F'; $UI.TxtNet.Text = 'Connecté à internet'
    } else {
        $UI.BdNet.Background = Get-Brush '#FDE7E9'; $UI.NetDot.Fill = Get-Brush '#C42B1C'
        $UI.TxtNet.Foreground = Get-Brush '#A4262C'; $UI.TxtNet.Text = 'Pas de connexion internet'
    }
    Update-LaunchState
}

# ---------------------------------------------------------------- Simulation du bouton Lancer
function Invoke-Simulation {
    $count = 0
    Write-Log '===== Simulation : actions prévues, dans leur ordre d''exécution =====' 'SIMU'

    Write-Log '1. Inventaire N/S + MAC : déjà exporté au démarrage' 'SIMU'

    foreach ($check in $script:UserChecks) {
        if ($check.IsChecked) {
            $user = $check.Tag
            Write-Log "2. Session locale : Remove-LocalUser '$($user.Name)' + suppression du profil $($user.ProfilePath)" 'SIMU'; $count++
        }
    }

    if ($UI.ChkOfficeC2R.IsChecked)      { Write-Log '3. Office Click-to-Run : ODT /configure avec <Remove All="TRUE"/>' 'SIMU'; $count++ }
    if ($UI.ChkOfficeMsi.IsChecked)      { Write-Log '3. Office MSI 2010-2016 : ODT /configure avec <RemoveMSI/>' 'SIMU'; $count++ }
    if ($UI.ChkOutlookClassic.IsChecked) { Write-Log '3. Outlook classique : retiré avec la suite Office' 'SIMU'; $count++ }
    if ($UI.ChkOutlookNew.IsChecked)     { Write-Log '3. Nouvel Outlook : Remove-AppxPackage -AllUsers + Remove-AppxProvisionedPackage (Microsoft.OutlookForWindows)' 'SIMU'; $count++ }
    if ($UI.ChkOneNote.IsChecked)        { Write-Log '3. OneNote : C2R + Appx Microsoft.Office.OneNote' 'SIMU'; $count++ }
    if ($UI.ChkTeams.IsChecked)          { Write-Log '3. Teams : MSI Teams Machine-Wide Installer + dossier local + Appx MSTeams + Appx MicrosoftTeams' 'SIMU'; $count++ }

    if ($UI.ChkOneDrive.IsChecked) {
        Write-Log '4. OneDrive : OneDriveSetup.exe /uninstall + clé Run du profil Default' 'SIMU'; $count++
        if ($UI.ChkOneDriveFolder.IsChecked) { Write-Log "4. Dossier OneDrive : Remove-Item '$($script:OneDriveFolder)' -Recurse" 'SIMU'; $count++ }
    }

    $selectedApps = @($script:AppChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    foreach ($app in ($selectedApps | Where-Object { $_.Silent })) {
        Write-Log "5. Désinstallation silencieuse ($($app.Method)) : $($app.Name) → $($app.Command)" 'SIMU'; $count++
    }
    foreach ($app in ($selectedApps | Where-Object { -not $_.Silent })) {
        Write-Log "5. Désinstallation avec assistant : $($app.Name) → $($app.Command)" 'ATTN'; $count++
    }

    $utilKey = Get-SelectedKey -Cards $script:UtilCards
    if ($utilKey) {
        $util = $script:Config.Utilities.$utilKey
        if ($util.DotNet) { Write-Log "6. Dépendance : runtime .NET Desktop adapté à la version de $($util.Tool) proposée par winget" 'SIMU'; $count++ }
        Write-Log "6. Utilitaire : winget install --id $($util.WingetId) --source $($util.WingetSource) --silent" 'SIMU'; $count++
    }

    $office = Get-OfficePlan
    if ($office) {
        Write-Log "7. Office : $($office.Name) via ODT dans $($script:Config.Office.OdtFolder), configuration.xml :" 'SIMU'; $count++
        foreach ($line in ($office.Xml -split "`r`n")) { Write-Log "     $line" 'SIMU' }
    }

    if ($UI.ChkAdobe.IsChecked) { Write-Log "8. Adobe Acrobat Reader : winget install --id $($script:Config.Adobe.WingetId) --silent" 'SIMU'; $count++ }

    foreach ($check in $script:NicChecks) {
        if ($check.IsChecked) { Write-Log "9. IPv6 : Disable-NetAdapterBinding -Name '$($check.Tag.Name)' -ComponentID ms_tcpip6" 'SIMU'; $count++ }
    }

    if ($UI.ChkPower.IsChecked) {
        $m = $script:Config.Power.MonitorTimeoutMinutes; $s = $script:Config.Power.StandbyTimeoutMinutes
        Write-Log "10. Alimentation : powercfg /change monitor-timeout-ac $m, monitor-timeout-dc $m, standby-timeout-ac $s, standby-timeout-dc $s" 'SIMU'; $count++
    }

    if ($utilKey -and $UI.ChkUtilUpdate.IsChecked) { Write-Log "11. MàJ utilitaire : $($script:Config.Utilities.$utilKey.UpdateCommand)" 'SIMU'; $count++ }
    if ($UI.ChkWU.IsChecked) { Write-Log '12. Windows Update : recherche, téléchargement et installation (API Microsoft.Update.Session)' 'SIMU'; $count++ }
    if ($UI.ChkHost.IsChecked) { Write-Log "13. Nom d'hôte : Rename-Computer -NewName '$($UI.TxtHost.Text)' (pris en compte au redémarrage)" 'SIMU'; $count++ }

    Write-Log "14. Simulation terminée : $count action(s) prévue(s), aucune modification du poste." 'OK'
    Write-Log 'Rappel, à faire à la main : RMM, antivirus, BitLocker, activation d''Office, redémarrage.' 'ATTN'
}

# ---------------------------------------------------------------- Événements
$UI.ChkHost.Add_Click({ Update-HostState })
$UI.TxtHost.Add_TextChanged({ Update-HostState })

$UI.ChkAllApps.Add_Click({
    $state = [bool]$UI.ChkAllApps.IsChecked
    foreach ($check in $script:AppChecks) { $check.IsChecked = $state }
})

$UI.ChkOneDrive.Add_Click({
    $UI.ChkOneDriveFolder.IsEnabled = [bool]$UI.ChkOneDrive.IsChecked
    if (-not $UI.ChkOneDrive.IsChecked) { $UI.ChkOneDriveFolder.IsChecked = $false }
})

foreach ($card in $script:UtilCards) {
    $card.Add_Click({
        param($source, $e)
        foreach ($other in $script:UtilCards) {
            if (-not [object]::ReferenceEquals($other, $source)) { $other.IsChecked = $false }
        }
        Update-UtilState
        $key = Get-SelectedKey -Cards $script:UtilCards
        if ($key) { Write-Log "Utilitaire sélectionné : $($script:Config.Utilities.$key.Tool) (téléchargement anticipé simulé)" 'SIMU' }
    })
}

foreach ($card in $script:OfficeCards) {
    $card.Add_Click({
        param($source, $e)
        foreach ($other in $script:OfficeCards) {
            if (-not [object]::ReferenceEquals($other, $source)) { $other.IsChecked = $false }
        }
        Update-OfficeState
    })
}

# Licence : exactement une des deux pastilles
$UI.PillTeams.Add_Click({ $UI.PillTeams.IsChecked = $true; $UI.PillNoTeams.IsChecked = $false; Update-OfficeState })
$UI.PillNoTeams.Add_Click({ $UI.PillNoTeams.IsChecked = $true; $UI.PillTeams.IsChecked = $false; Update-OfficeState })

foreach ($name in 'ChkIncNewOutlook', 'ChkIncClassicOutlook', 'ChkIncOneDrive') {
    $UI[$name].Add_Click({ Update-OfficeState })
}

$UI.BtnCopy.Add_Click({
    try {
        [System.Windows.Clipboard]::SetText($script:InventoryText)
        Write-Log 'N/S et adresses MAC copiés dans le presse-papiers' 'OK'
    } catch { Write-Log "Copie impossible : $($_.Exception.Message)" 'ERREUR' }
})

$UI.BtnGo.Add_Click({
    try { Invoke-Simulation }
    catch { Write-Log "Erreur pendant la simulation : $($_.Exception.Message)" 'ERREUR' }
})

# ---------------------------------------------------------------- Test de connexion périodique (non bloquant)
$script:Http = New-Object System.Net.Http.HttpClient
$script:Http.Timeout = [TimeSpan]::FromSeconds(4)
$script:NetTask = $null
$script:NetNext = Get-Date
$script:NetKnown = $false

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    if ($script:NetTask) {
        if ($script:NetTask.IsCompleted) {
            $ok = $false
            if ($script:NetTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $ok = ([string]$script:NetTask.Result).Contains($script:Config.InternetTestExpected)
            }
            $script:NetTask = $null
            $script:NetNext = (Get-Date).AddSeconds([int]$script:Config.InternetTestIntervalSeconds)
            Set-NetState -Ok $ok
        }
    } elseif ((Get-Date) -ge $script:NetNext) {
        try { $script:NetTask = $script:Http.GetStringAsync([string]$script:Config.InternetTestUrl) }
        catch { $script:NetNext = (Get-Date).AddSeconds(5); Set-NetState -Ok $false }
    }
})

$Window.Add_ContentRendered({
    try {
        Write-Log "Journal : $($script:LogFile)"
        Initialize-Detections
        Update-UtilState
        Update-OfficeState
        Update-HostState
    } catch {
        Write-Log "Erreur pendant les détections : $($_.Exception.Message)" 'ERREUR'
    }
    $timer.Start()
})

$Window.Add_Closed({
    $timer.Stop()
    $script:Http.Dispose()
})

try {
    [void]$Window.ShowDialog()
} catch {
    [System.Windows.MessageBox]::Show("Erreur inattendue :`n$($_.Exception.Message)", 'Préparation de poste', 'OK', 'Error') | Out-Null
    exit 1
}
