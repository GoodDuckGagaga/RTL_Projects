$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDirectory = Split-Path -Parent $scriptDirectory
$buildDirectory = Join-Path $projectDirectory 'build'
$simulationImage = Join-Path $buildDirectory 'uart_core_tb.vvp'

New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null

Push-Location $projectDirectory
try {
    & iverilog -g2012 -Wall -Wno-timescale -s tb_uart_core -o $simulationImage -c filelist.f
    if ($LASTEXITCODE -ne 0) { throw "iverilog failed with exit code $LASTEXITCODE" }

    & vvp $simulationImage
    if ($LASTEXITCODE -ne 0) { throw "vvp failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
