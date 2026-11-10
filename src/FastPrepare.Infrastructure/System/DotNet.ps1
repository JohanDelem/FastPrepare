<#
    Runtimes .NET Desktop installés (dépendance de Dell Command Update).
#>

$script:DesktopRuntimeKeys = @(
    'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App',
    'HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x86\sharedfx\Microsoft.WindowsDesktop.App'
)

function Get-DotNetDesktopRuntimeVersion {
    <# Versions de Microsoft.WindowsDesktop.App installées (x64 et x86), sans doublon. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    $versions = foreach ($key in $script:DesktopRuntimeKeys) {
        $values = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $values) { continue }
        foreach ($property in $values.PSObject.Properties) {
            if ($property.Name -match '^\d+\.\d+\.\d+') { $property.Name }
        }
    }
    return @($versions | Sort-Object -Unique)
}
