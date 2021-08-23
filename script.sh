#!/bin/sh
commandlist="wget gzip xorriso shasum md5sum"
dir_extraction="extract"
iso_vanilla_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.0.0-amd64-netinst.iso"
iso_vanilla=$(basename $iso_vanilla_url)
iso_vanilla_checksum_url=$(echo "$iso_vanilla_url" | sed "s/$iso_vanilla/SHA512SUMS/g")
iso_preseed=$(echo "$iso_vanilla" | sed "s/.iso/-preseed.iso/g")

for command in $commandlist
do
  if ! command -v "$command" $> /dev/null; then
    echo "Error: $command could not be found."
    exit
  fi
done

if $(cpio --version | grep -q "bsdcpio"); then
  echo "Error: cpio version not supported. Please install GNU cpio."
  exit
fi

if [ ! -f preseed.cfg ]; then
  echo "Error: preseed.cfg could not be found. Please create it in the same directory."
  exit
fi

if [ ! -f "$iso_vanilla" ]; then
  echo "Downloading ISO..."
  wget -q --show-progress "$iso_vanilla_url"
  if [ ! -f "$iso_vanilla" ]; then
    echo "Error: ISO could not be downloaded. Please check your internet connection."
    exit
  fi
else
  echo "Info: ISO was found. Not redownloading."
fi

echo "Downloading and validating ISO checksum..."
iso_checksum=$(wget -O - -o /dev/null "$iso_vanilla_checksum_url" | grep "$iso_vanilla" | awk '{ print $1 }')
if [ ! "$(shasum -a 512 "$iso_vanilla" | awk '{ print $1 }')" = "$iso_checksum" ]; then
  rm -f "$iso_vanilla"
  echo "Outdated or corrupt ISO has been removed. Check your internet connection and rerun the script."
  exit
fi

if [ ! -d $dir_extraction ]; then
  mkdir $dir_extraction
else
  echo "Warning: Extraction folder was found. Cleaning directory..."
  sleep 1
  chmod -R +w $dir_extraction
  rm -rf $dir_extraction
  mkdir $dir_extraction
fi

echo "Extracting ISO and initrd..."
xorriso -osirrox on -indev "$iso_vanilla" -extract / $dir_extraction 2>/dev/null
cd $dir_extraction || exit
chmod -R +w install.amd/
gunzip install.amd/initrd.gz
echo "Injecting preseed.cfg..."
cp ../preseed.cfg preseed.cfg
echo preseed.cfg | cpio --quiet -H newc -o -A -F install.amd/initrd
rm preseed.cfg
echo "Compressing initrd..."
gzip install.amd/initrd
chmod -R -w install.amd/
chmod +w boot/grub/grub.cfg
printf "linux /install.amd/vmlinuz auto=true vga=788 quiet \ninitrd /install.amd/initrd.gz\nboot" > boot/grub/grub.cfg
chmod -w boot/grub/grub.cfg
echo "Generating new checksums..."
chmod +w md5sum.txt
find . -follow -type f ! -name md5sum.txt -print0 2>/dev/null | xargs -0 md5sum > md5sum.txt
chmod -w md5sum.txt
cd .. || exit
echo "Generating ISO..."
xorriso -as mkisofs -e boot/grub/efi.img -no-emul-boot -o "$iso_preseed" "$dir_extraction" 2>/dev/null
chmod -R +w $dir_extraction
rm -rf $dir_extraction
