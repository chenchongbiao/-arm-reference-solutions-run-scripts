#!/bin/bash

# Copyright (c) 2021-2023, ARM Limited and Contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of ARM nor the names of its contributors may be used
# to endorse or promote products derived from this software without specific
# prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

RUN_SCRIPTS_DIR=$(dirname "$0")

#The help text.
#NOTE: The OPTIONS below are misaligned on purpose so that they appear aligned when the script is called.
help_text () {
	echo "<path_to_run_model.sh> [OPTIONS]"
	echo "OPTIONS:"
	echo "-m, --model				path to model"
	echo "-d, --distro				distro version, values supported [buildroot, android-fvp, debian]"
	echo "-b, --bl33                                bl33, values supported [u-boot, uefi]. This flag valid only for debian"
	echo "-a, --avb				[OPTIONAL] avb boot, values supported [true, false], DEFAULT: false"
	echo "-t, --tap-interface			[OPTIONAL] tap interface"
	echo "-n, --networking			[OPTIONAL] networking, values supported [user, tap, none]"
	echo "					DEFAULT: tap if tap interface provided, otherwise user"
	echo "--					[OPTIONAL] After -- pass all further options directly to the model"
	exit 1
}

incorrect_script_use () {
	echo "Incorrect script use, call script as:"
	help_text
}

# check if directory exits and exit if it doesnt
check_dir_exists_and_exit () {
	if [ ! -d $1 ]
	then
		echo "directory for $2: $1 doesnt exist"
		exit 1
	fi
}

# check if first argument is a substring of 2nd argument and exit if thats not
# the case
check_substring_and_exit () {

	if [[ ! "$1" =~ "$2" ]]
	then
		echo "$1 does not contain $2"
		exit 1
	fi
}

# check if file exits and exit if it doesnt
check_file_exists_and_exit () {
	if [ ! -f $1 ]
	then
		echo "$1 does not exist"
		exit 1
	fi
}
check_android_images () {
	check_file_exists_and_exit $DEPLOY_DIR/system.img
	check_file_exists_and_exit $DEPLOY_DIR/userdata.img
	[ "$AVB" == true ] && check_file_exists_and_exit $DEPLOY_DIR/vbmeta.img
	[ "$AVB" == true ] && check_file_exists_and_exit $DEPLOY_DIR/boot.img
}

AVB=false
NETWORKING=user
BL33=u-boot

while [[ $# -gt 0 ]]
do
	key="$1"

	case $key in
	    -m|--model)
		    MODEL="$2"
		    shift
		    shift
		    ;;
	    -d|--distro)
		    DISTRO="$2"
		    shift
		    shift
		    ;;
	    -t|--tap-interface)
		    TAP_INTERFACE="$2"
		    NETWORKING=tap
		    shift
		    shift
		    ;;
	    -n|--networking)
		    NETWORKING="$2"
		    shift
		    shift
		    ;;
	    -a|--avb)
		    AVB="$2"
		    shift
		    shift
		    ;;
	    -b|--bl33)
		    BL33="$2"
		    shift
		    shift
		    ;;
	    -h|--help)
		    help_text
		    ;;
	    --)
		    shift
		    break
		    ;;
		*)
			incorrect_script_use
	esac
done

[ -z "$MODEL" ] && incorrect_script_use || echo "MODEL=$MODEL"
[ -z "$DISTRO" ] && incorrect_script_use || echo "DISTRO=$DISTRO"
[ -z "$BL33" ] && incorrect_script_use || echo "BL33=$BL33"
echo "TAP_INTERFACE=$TAP_INTERFACE"
echo "NETWORKING=$NETWORKING"
echo "AVB=$AVB"
echo "BL33=$BL33"

if [ ! -f "$MODEL" ]; then
    echo "Path provided for model :$1 does not exist"
    exit 1
fi

echo
echo "Launching model: "`basename $MODEL`
$MODEL --version

DEPLOY_DIR=$RUN_SCRIPTS_DIR/../../output/${DISTRO}/deploy/tc2/
DEB_MMC_IMAGE_NAME=debian_fs.img
GRUB_DISK_IMAGE=$DEPLOY_DIR/grub-$DISTRO.img

check_dir_exists_and_exit $DEPLOY_DIR "firmware and kernel images"

case $DISTRO in
    buildroot)
		DISTRO_MODEL_PARAMS="--data board.dram=${DEPLOY_DIR}/tc-fitImage.bin@0x20000000"
        BL1_IMAGE_FILE="$DEPLOY_DIR/bl1-tc.bin"
        FIP_IMAGE_FILE="$DEPLOY_DIR/fip_gpt-tc.bin"
        RSS_ROM_FILE="$DEPLOY_DIR/rss_rom.bin"
	RSS_CM_PROV_BUNDLE="$DEPLOY_DIR/rss_encrypted_cm_provisioning_bundle_0.bin"
	RSS_DM_PROV_BUNDLE="$DEPLOY_DIR/rss_encrypted_dm_provisioning_bundle.bin"
        ;;
    android-fvp)
		DISTRO_MODEL_PARAMS="-C board.virtioblockdevice.image_path=$DEPLOY_DIR/android.img"
		[ "$AVB" == true ] || DISTRO_MODEL_PARAMS="$DISTRO_MODEL_PARAMS \
			--data board.dram=$DEPLOY_DIR/ramdisk_uboot.img@0x8000000 \
			--data board.dram=$DEPLOY_DIR/Image@0x80000 "
        BL1_IMAGE_FILE="$DEPLOY_DIR/bl1-trusty-tc.bin"
        FIP_IMAGE_FILE="$DEPLOY_DIR/fip-trusty-tc.bin"
        RSS_ROM_FILE="$DEPLOY_DIR/rss_trusty_rom.bin"
	RSS_CM_PROV_BUNDLE="$DEPLOY_DIR/rss_trusty_encrypted_cm_provisioning_bundle_0.bin"
	RSS_DM_PROV_BUNDLE="$DEPLOY_DIR/rss_trusty_encrypted_dm_provisioning_bundle.bin"
        ;;
     debian)
        if [[ $BL33 == "uefi" ]]; then
               DISTRO_MODEL_PARAMS="-C board.virtioblockdevice.image_path=$GRUB_DISK_IMAGE"
        elif [[ $BL33 == "u-boot" ]]; then
               DISTRO_MODEL_PARAMS="--data board.dram=${DEPLOY_DIR}/Image@0x80000 \
                           -C board.mmc.p_mmc_file=$DEPLOY_DIR/$DEB_MMC_IMAGE_NAME"
        fi
        BL1_IMAGE_FILE="$DEPLOY_DIR/bl1-tc.bin"
        FIP_IMAGE_FILE="$DEPLOY_DIR/fip_gpt-tc.bin"
        RSS_ROM_FILE="$DEPLOY_DIR/rss_rom.bin"
	RSS_CM_PROV_BUNDLE="$DEPLOY_DIR/rss_encrypted_cm_provisioning_bundle_0.bin"
	RSS_DM_PROV_BUNDLE="$DEPLOY_DIR/rss_encrypted_dm_provisioning_bundle.bin"
        ;;

    *) echo "bad option for distro $3"; incorrect_script_use
        ;;
esac

echo "DISTRO_MODEL_PARAMS=$DISTRO_MODEL_PARAMS"

case $NETWORKING in
    tap)
	echo "Enabling networking with interface $TAP_INTERFACE"
	NETWORKING_MODEL_PARAMS="-C board.hostbridge.interfaceName="$TAP_INTERFACE" \
	-C board.smsc_91c111.enabled=1 \
	"
	;;
    user)
	echo "Enabling user networking"
	NETWORKING_MODEL_PARAMS="-C board.smsc_91c111.enabled=1 \
	-C board.hostbridge.userNetworking=1 \
	-C board.hostbridge.userNetPorts=\"5555=5555,8080=80,8022=22\""
	;;
    none)
	;;
    *)
	echo "bad option for networking: $NETWORKING"; incorrect_script_use
	;;
esac

# using an absolute path to be able to run script from any
# directory without breaking a softlink
LOGS_DIR="$(realpath --no-symlinks "$(dirname "${BASH_SOURCE[0]}")")"/logs
BOOT_LOGS_DIR=$LOGS_DIR/$DISTRO/$(date +"%Y_%m_%d_%I_%M_%p")
LATEST_LOGS=$LOGS_DIR/$DISTRO/latest
# delete latest logs from last run
rm -f $LATEST_LOGS
mkdir -p $BOOT_LOGS_DIR
ln -s $BOOT_LOGS_DIR $LATEST_LOGS

set -x

"$MODEL" \
    -C board.flashloader0.fname=${FIP_IMAGE_FILE} \
    -C soc.pl011_uart0.out_file=$BOOT_LOGS_DIR/uart0_soc.log \
    -C soc.pl011_uart0.unbuffered_output=1 \
    -C css.pl011_uart_ap.out_file=$BOOT_LOGS_DIR/uart_ap.log \
    -C css.pl011_uart_ap.unbuffered_output=1 \
    -C css.pl011_uart1_ap.out_file=$BOOT_LOGS_DIR/uart1_ap.log \
    -C css.pl011_uart1_ap.unbuffered_output=1 \
    -C displayController=2 \
    -C css.rss.rom.raw_image=${RSS_ROM_FILE} \
    -C css.rss.VMADDRWIDTH=19 \
    -C css.rss.CMU0_NUM_DB_CH=16 \
    --data css.rss.sram0=${RSS_CM_PROV_BUNDLE}@0x0 \
    --data css.rss.sram1=${RSS_DM_PROV_BUNDLE}@0x80000 \
    -C css.cluster0.subcluster0.has_ete=1 \
    -C css.cluster0.subcluster1.has_ete=1 \
    -C css.cluster0.subcluster2.has_ete=1 \
    ${NETWORKING_MODEL_PARAMS} \
    ${DISTRO_MODEL_PARAMS} \
    "$@"

exit $?
