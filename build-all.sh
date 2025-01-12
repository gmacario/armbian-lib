#!/bin/bash
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# Include here to make "display_alert" and "prepare_host" available
source $SRC/lib/general.sh

# Script parameters handling
for i in "$@"; do
	if [[ $i == *=* ]]; then
		parameter=${i%%=*}
		value=${i##*=}
		display_alert "Command line: setting $parameter to" "${value:-(empty)}" "info"
		eval $parameter=$value
	fi
done

FORCEDRELEASE=$RELEASE

# when we want to build from certain start
from=0

rm -rf /run/armbian
mkdir -p /run/armbian
RELEASE_LIST=("xenial" "jessie")
BRANCH_LIST=("default" "next" "dev")

pack_upload ()
{
# pack into .7z and upload to server

# stage: init
display_alert "Signing and compressing" "Please wait!" "info"
local version="Armbian_${REVISION}_${BOARD^}_${DISTRIBUTION}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"
local subdir="archive"
[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
[[ $BETA == yes ]] && local subdir=nightly
local filename=$CACHEDIR/$DESTIMG/${version}.7z

# stage: generate sha256sum.sha
cd $CACHEDIR/$DESTIMG
sha256sum -b ${version}.img > sha256sum.sha

# stage: sign with PGP
if [[ -n $GPG_PASS ]]; then
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes ${version}.img
	echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --batch --yes armbian.txt
fi

# create remote directory structure
ssh ${SEND_TO_SERVER} "mkdir -p /var/www/dl.armbian.com/${BOARD}/{archive,nightly};";

# pack and move file to server under new process
nice -n 19 bash -c "\
7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img armbian.txt *.asc sha256sum.sha >/dev/null 2>&1 ; \
find . -type f -not -name '*.7z' -print0 | xargs -0 rm -- ; \
while ! rsync -arP $CACHEDIR/$DESTIMG/. -e 'ssh -p 22' ${SEND_TO_SERVER}:/var/www/dl.armbian.com/${BOARD}/${subdir};do sleep 5;done; \
rm -r $CACHEDIR/$DESTIMG" &
}

build_main ()
{
touch "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}.pid";
source $SRC/lib/main.sh;
[[ $KERNEL_ONLY != yes ]] && pack_upload
rm "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}.pid"
}


create_images_list()
{
	#
	# if parameter is true, than we build beta list
	#
	for board in $SRC/lib/config/boards/*.conf; do
		BOARD=$(basename $board | cut -d'.' -f1)
		source $SRC/lib/config/boards/$BOARD.conf
		if [[ -n $CLI_TARGET && -z $1 ]]; then

			# RELEASES : BRANCHES
			CLI_TARGET=($(tr ':' ' ' <<< "$CLI_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${CLI_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${CLI_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release no")
				done
			done
		fi
		if [[ -n $DESKTOP_TARGET && -z $1 ]]; then

			# RELEASES : BRANCHES
			DESKTOP_TARGET=($(tr ':' ' ' <<< "$DESKTOP_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${DESKTOP_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${DESKTOP_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release yes")
				done
			done

		fi
		if [[ -n $CLI_BETA_TARGET && -n $1 ]]; then

			# RELEASES : BRANCHES
			CLI_BETA_TARGET=($(tr ':' ' ' <<< "$CLI_BETA_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${CLI_BETA_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${CLI_BETA_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release no")
				done
			done

		fi
		if [[ -n $DESKTOP_BETA_TARGET && -n $1 ]]; then

			# RELEASES : BRANCHES
			DESKTOP_BETA_TARGET=($(tr ':' ' ' <<< "$DESKTOP_BETA_TARGET"))

			build_settings_target=($(tr ',' ' ' <<< "${DESKTOP_BETA_TARGET[0]}"))
			build_settings_branch=($(tr ',' ' ' <<< "${DESKTOP_BETA_TARGET[1]}"))

			[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
			[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

			for release in ${build_settings_target[@]}; do
				for kernel in ${build_settings_branch[@]}; do
					buildlist+=("$BOARD $kernel $release yes")
				done
			done

		fi

		unset CLI_TARGET CLI_BRANCH DESKTOP_TARGET DESKTOP_BRANCH KERNEL_TARGET CLI_BETA_TARGET DESKTOP_BETA_TARGET
	done
}

create_kernels_list()
{
	for board in $SRC/lib/config/boards/*.conf; do
		BOARD=$(basename $board | cut -d'.' -f1)
		source $SRC/lib/config/boards/$BOARD.conf
		if [[ -n $KERNEL_TARGET ]]; then
			for kernel in $(tr ',' ' ' <<< $KERNEL_TARGET); do
				buildlist+=("$BOARD $kernel")
			done
		fi
		unset KERNEL_TARGET
	done
}

buildlist=()

if [[ $KERNEL_ONLY == yes ]]; then
	create_kernels_list
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH
else
	create_images_list $BETA
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH RELEASE DESKTOP
fi

n=0
for line in "${buildlist[@]}"; do
	n=$[$n+1]
	printf "%-3s %-20s %-10s %-10s %-10s\n" $n $line
done
echo -e "\n${#buildlist[@]} total\n"

[[ $BUILD_ALL == demo ]] && exit 0

buildall_start=`date +%s`
n=0
for line in "${buildlist[@]}"; do
	unset LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH UBOOT_NEEDS_GCC KERNEL_NEEDS_GCC \
		CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE \
		write_uboot_platform family_tweaks setup_write_uboot_platform BOOTSCRIPT UBOOT_TARGET_MAP LOCALVERSION UBOOT_COMPILER KERNEL_COMPILER \
		MODULES MODULES_NEXT MODULES_DEV INITRD_ARCH HAS_UUID_SUPPORT BOOTENV_FILE BOOTDELAY MODULES_BLACKLIST MODULES_BLACKLIST_NEXT \
		MODULES_BLACKLIST_DEV MOUNT SDCARD BOOTPATCHDIR buildtext RELEASE UBOOT_ALT_GCC KERNEL_ALT_GCC IMAGE_TYPE

	read BOARD BRANCH RELEASE BUILD_DESKTOP <<< $line
	n=$[$n+1]
	[[ -z $RELEASE ]] && RELEASE=$FORCEDRELEASE;
	if [[ $from -le $n ]]; then
		[[ -z $BUILD_DESKTOP ]] && BUILD_DESKTOP="no"
		jobs=$(ls /run/armbian | wc -l)
		if [[ $jobs -lt $MULTITHREAD ]]; then
			display_alert "Building in the back $n / ${#buildlist[@]}" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
			(build_main) &
			[[ $KERNEL_ONLY != yes ]] && sleep $(( ( RANDOM % 10 )  + 1 ))
		else
			display_alert "Building $buildtext $n / ${#buildlist[@]}" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
			build_main
		fi

	fi
done

buildall_end=`date +%s`
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime" "$buildall_runtime min" "info"
