param(
    [ValidateSet("static", "shared", "all", "clean")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..").Path
$Spn = "$Root\.spn"
$Store = "$Spn\store\x86_64-windows-msvc"
$Build = "$Spn\build\msvc"
$TccDefs = "/DONE_SOURCE=1 /DTCC_TARGET_PE /DTCC_TARGET_X86_64"
$TccInc = "/I`"$Root`""
$Warnings = "/W2 /wd4244 /wd4267 /wd4996 /wd4018 /wd4146"
$ClFlags = "/O2 /nologo /MT /GS- $Warnings"

# Windows config.h: no CONFIG_LDDIR (Linux-only, for GNU ld script workaround)
function Write-ConfigH {
    $cfg = "$Root\config.h"
    Set-Content $cfg '#define TCC_VERSION "0.9.28rc"'
}

function Build-Runtime {
    param([string]$TccExe, [string]$OutDir)

    $rtLib = "$OutDir\lib"
    New-Item -ItemType Directory -Force -Path $rtLib | Out-Null

    # Runtime lib sources
    $libSrc = @(
        "lib\libtcc1.c", "lib\stdatomic.c", "lib\builtin.c",
        "lib\alloca.S", "lib\alloca-bt.S", "lib\atomic.S"
    )
    $winSrc = @(
        "win32\lib\crt1.c", "win32\lib\crt1w.c",
        "win32\lib\wincrt1.c", "win32\lib\wincrt1w.c",
        "win32\lib\dllcrt1.c", "win32\lib\dllmain.c",
        "win32\lib\chkstk.S"
    )

    foreach ($f in ($libSrc + $winSrc)) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f)
        Write-Host "  rt: $name"
        & $TccExe -B "$Root\win32" -I $Root -I "$Root\include" `
            -c "$Root\$f" -o "$rtLib\$name.o"
        if ($LASTEXITCODE -ne 0) { throw "Failed to compile $f" }
    }

    # Archive
    $objs = Get-ChildItem "$rtLib\*.o" | ForEach-Object { $_.FullName }
    & $TccExe -ar "$rtLib\libtcc1.a" @objs
    if ($LASTEXITCODE -ne 0) { throw "Failed to create libtcc1.a" }

    # Extra objects
    $extra = @(
        @("lib\bcheck.c", "-bt"),
        @("lib\bt-exe.c", ""),
        @("lib\bt-log.c", ""),
        @("lib\bt-dll.c", ""),
        @("lib\runmain.c", "")
    )
    foreach ($e in $extra) {
        $f = $e[0]; $flag = $e[1]
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f)
        Write-Host "  extra: $name"
        $cmd = @("-B", "$Root\win32", "-I", $Root, "-I", "$Root\include",
                 "-c", "$Root\$f", "-o", "$rtLib\$name.o")
        if ($flag) { $cmd += $flag }
        & $TccExe @cmd
        if ($LASTEXITCODE -ne 0) { throw "Failed to compile $f" }
    }

    # Copy .def files
    Copy-Item "$Root\win32\lib\*.def" $rtLib

    # Copy headers
    $incDir = "$OutDir\include"
    New-Item -ItemType Directory -Force -Path $incDir | Out-Null
    Copy-Item "$Root\include\*" $incDir -Recurse -Force
    Copy-Item "$Root\win32\include\*" $incDir -Recurse -Force
}

function Build-Static {
    Write-Host "=== MSVC static ==="
    $out = "$Store\static"
    $bld = "$Build\static"
    New-Item -ItemType Directory -Force -Path $bld | Out-Null

    Write-ConfigH

    # libtcc.lib
    Write-Host "  compiling libtcc.lib"
    $clArgs = "$ClFlags $TccDefs /DCONFIG_TCC_STATIC=1 $TccInc /c `"$Root\libtcc.c`" /Fo`"$bld\libtcc.obj`""
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl failed" }
    lib /nologo "/OUT:$bld\libtcc.lib" "$bld\libtcc.obj"
    if ($LASTEXITCODE -ne 0) { throw "lib failed" }

    # tcc.exe (for building runtime)
    Write-Host "  compiling tcc.exe"
    $clArgs = "$ClFlags $TccDefs /DCONFIG_TCC_STATIC=1 /DONE_SOURCE=0 $TccInc `"$Root\tcc.c`" `"$bld\libtcc.lib`" /Fe`"$bld\tcc.exe`" /link shlwapi.lib advapi32.lib shell32.lib"
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl tcc.exe failed" }

    # Runtime
    Write-Host "  building runtime"
    Build-Runtime "$bld\tcc.exe" "$bld\runtime"

    # Install
    Write-Host "  installing"
    New-Item -ItemType Directory -Force -Path "$out\lib", "$out\include", "$out\bin", "$out\lib\tcc" | Out-Null
    Copy-Item "$bld\libtcc.lib" "$out\lib\"
    Copy-Item "$Root\libtcc.h" "$out\include\"
    Copy-Item "$bld\runtime\lib" "$out\lib\tcc\" -Recurse -Force
    Copy-Item "$bld\runtime\include" "$out\lib\tcc\" -Recurse -Force

    # hello.exe
    Write-Host "  compiling hello.exe"
    $clArgs = "$ClFlags /I`"$out\include`" `"$Spn\hello.c`" `"$out\lib\libtcc.lib`" /Fe`"$out\bin\hello.exe`" /link shlwapi.lib advapi32.lib shell32.lib"
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl hello.exe failed" }

    Write-Host "  testing"
    & "$out\bin\hello.exe" "$out\lib\tcc"
    if ($LASTEXITCODE -ne 0) { throw "hello.exe failed" }
    Write-Host "=== MSVC static OK ==="
}

function Build-Shared {
    Write-Host "=== MSVC shared ==="
    $out = "$Store\shared"
    $bld = "$Build\shared"
    New-Item -ItemType Directory -Force -Path $bld | Out-Null

    Write-ConfigH

    # libtcc.dll
    Write-Host "  compiling libtcc.dll"
    $clArgs = "$ClFlags $TccDefs /DLIBTCC_AS_DLL $TccInc /LD `"$Root\libtcc.c`" /Fe`"$bld\libtcc.dll`" /link /IMPLIB:`"$bld\libtcc.lib`" shlwapi.lib advapi32.lib shell32.lib"
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl libtcc.dll failed" }

    # tcc.exe (link against DLL)
    Write-Host "  compiling tcc.exe"
    $clArgs = "$ClFlags $TccDefs /DONE_SOURCE=0 $TccInc `"$Root\tcc.c`" `"$bld\libtcc.lib`" /Fe`"$bld\tcc.exe`" /link shlwapi.lib advapi32.lib shell32.lib"
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl tcc.exe failed" }

    # DLL is already next to tcc.exe in $bld

    # Runtime
    Write-Host "  building runtime"
    Build-Runtime "$bld\tcc.exe" "$bld\runtime"

    # Install
    Write-Host "  installing"
    New-Item -ItemType Directory -Force -Path "$out\lib", "$out\include", "$out\bin", "$out\lib\tcc" | Out-Null
    Copy-Item "$bld\libtcc.dll" "$out\bin\"
    Copy-Item "$bld\libtcc.lib" "$out\lib\"
    Copy-Item "$Root\libtcc.h" "$out\include\"
    Copy-Item "$bld\runtime\lib" "$out\lib\tcc\" -Recurse -Force
    Copy-Item "$bld\runtime\include" "$out\lib\tcc\" -Recurse -Force

    # hello.exe
    Write-Host "  compiling hello.exe"
    $clArgs = "$ClFlags /I`"$out\include`" `"$Spn\hello.c`" `"$out\lib\libtcc.lib`" /Fe`"$out\bin\hello.exe`" /link shlwapi.lib advapi32.lib shell32.lib"
    cmd /c "cl $clArgs"
    if ($LASTEXITCODE -ne 0) { throw "cl hello.exe failed" }

    Write-Host "  testing"
    & "$out\bin\hello.exe" "$out\lib\tcc"
    if ($LASTEXITCODE -ne 0) { throw "hello.exe failed" }
    Write-Host "=== MSVC shared OK ==="
}

function Clean-All {
    Write-Host "Cleaning MSVC builds"
    if (Test-Path "$Build") { Remove-Item -Recurse -Force "$Build" }
    if (Test-Path "$Store") { Remove-Item -Recurse -Force "$Store" }
    if (Test-Path "$Root\config.h") { Remove-Item "$Root\config.h" }
    # cl drops obj/pdb in cwd
    Get-ChildItem $Spn -Include *.obj, *.pdb, *.ilk, *.exp -Recurse | Remove-Item -Force
    Write-Host "Clean done"
}

switch ($Target) {
    "static" { Build-Static }
    "shared" { Build-Shared }
    "all"    { Build-Static; Build-Shared }
    "clean"  { Clean-All }
}
