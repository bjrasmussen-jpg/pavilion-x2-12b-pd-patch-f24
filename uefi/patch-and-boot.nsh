echo HP pre-EBS patch: refreshing device mappings...
map -r

if exist fs0:\PatchS3Fpr2.efi then
  goto usb0
endif
if exist fs1:\PatchS3Fpr2.efi then
  goto usb1
endif
if exist fs2:\PatchS3Fpr2.efi then
  goto usb2
endif
if exist fs3:\PatchS3Fpr2.efi then
  goto usb3
endif
if exist fs4:\PatchS3Fpr2.efi then
  goto usb4
endif
if exist fs5:\PatchS3Fpr2.efi then
  goto usb5
endif
if exist fs6:\PatchS3Fpr2.efi then
  goto usb6
endif
if exist fs7:\PatchS3Fpr2.efi then
  goto usb7
endif
if exist fs8:\PatchS3Fpr2.efi then
  goto usb8
endif
if exist fs9:\PatchS3Fpr2.efi then
  goto usb9
endif

echo ERROR: PatchS3Fpr2.efi was not found on fs0 through fs9.
echo Nothing was changed. Run map -r and inspect the mappings.
pause
exit /b 10

:usb0
fs0:
cd \
goto runpatch
:usb1
fs1:
cd \
goto runpatch
:usb2
fs2:
cd \
goto runpatch
:usb3
fs3:
cd \
goto runpatch
:usb4
fs4:
cd \
goto runpatch
:usb5
fs5:
cd \
goto runpatch
:usb6
fs6:
cd \
goto runpatch
:usb7
fs7:
cd \
goto runpatch
:usb8
fs8:
cd \
goto runpatch
:usb9
fs9:
cd \

:runpatch
echo HP_PRE_EBS_PATCH_V2_BEGIN > uefi-patch-result.txt
PatchS3Fpr2.efi >> uefi-patch-result.txt
set patchstatus %lasterror%
echo PATCH_STATUS=%patchstatus% >> uefi-patch-result.txt
type uefi-patch-result.txt

if %patchstatus% == 0 then
  echo Patch verified. Starting Windows in the SAME boot...
  goto bootwindows
endif

echo ERROR: volatile S3 patch failed. Windows will not be started.
echo The SPI flash was not changed.
pause
exit /b 11

:bootwindows
map -r
if exist fs0:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs0:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs1:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs1:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs2:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs2:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs3:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs3:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs4:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs4:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs5:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs5:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs6:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs6:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs7:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs7:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs8:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs8:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs9:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs9:\EFI\Microsoft\Boot\bootmgfw.efi
endif

echo ERROR: Windows boot manager was not found on fs0 through fs9.
echo Do not reboot. Run map -r and start EFI\Microsoft\Boot\bootmgfw.efi manually.
pause
exit /b 12
