#!/usr/bin/bash
set -e
cd $(dirname $0)
WORKDIR=$(pwd -P)
##########################################################
## ISO SETTING
OFFICIAL_ISO="CentOS-7-x86_64-Minimal-2207-02.iso"
MIRROR_URL="http://mirrors.163.com/centos/7.9.2009/isos/x86_64/"
TARGET_ISO="Customize-CentOS-7-x86_64-"$(date +%F)".iso"

#!!!! this label must be same as inst.stage2=hd:LABEL=XXXX
ISO_LABEL="CUSTOM"

## KVM SETTING(Optional)
VM_NAME="centos7c"
VM_CPU=4
VM_RAM=4096
VNC_PORT_BIOS=5936
VNC_PORT_UEFI=5937

## CUSTOM WORKDIR SETTING
ISO_MOUNT_DIR="centos_official"
ISO_CUSTOM_DIR="centos_customize"
RPM_CUSTOM_DIR="rpms"
CONF_CUSTOM_DIR="config"

START_MODE="bios"
##########################################################
function show_msg() {
    CURTIME=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[1;32m[${CURTIME}] $1\033[0m"
}
##########################################################

function download_official_iso() {
  if [ ! -f ${OFFICIAL_ISO} ] ; then
    show_msg "Downloading ${OFFICIAL_ISO} ... "
    curl -# -Lo ${OFFICIAL_ISO}  ${MIRROR_URL}${OFFICIAL_ISO}

    show_msg "Checking ISO MD5 ... "
    checkisomd5 ${OFFICIAL_ISO}
  fi
}

# isolinux.cfg and kickstart files
function copy_custom_config() {
  show_msg "Copying config files ..."
  /usr/bin/cp -f ${CONF_CUSTOM_DIR}/isolinux.cfg    ${ISO_CUSTOM_DIR}/isolinux/
  /usr/bin/cp -f ${CONF_CUSTOM_DIR}/kickstart/*.cfg ${ISO_CUSTOM_DIR}/isolinux/
  if [ -f ${CONF_CUSTOM_DIR}/splash.png ] ; then
    /usr/bin/cp -f ${CONF_CUSTOM_DIR}/splash.png    ${ISO_CUSTOM_DIR}/isolinux/
  fi
  if [ -f ${CONF_CUSTOM_DIR}/uefi-grub.cfg ] ; then
    /usr/bin/cp -f ${CONF_CUSTOM_DIR}/uefi-grub.cfg ${ISO_CUSTOM_DIR}/EFI/BOOT/grub.cfg
  fi
}

function copy_custom_files() {
  show_msg "Copying custom files ..."
}

function copy_custom_rpms() {
  RPM_COUNT=$(ls ${RPM_CUSTOM_DIR}/*.rpm 2>/dev/null|wc -l)
  if [ "${RPM_COUNT}" != "0" ] ; then
     show_msg "Copying config rpm packages(${RPM_COUNT}) ..."
     cp -f ${RPM_CUSTOM_DIR}/*.rpm ${ISO_CUSTOM_DIR}/Packages/
     show_msg "Generating new rpm  repodata ..."
     mv ${ISO_CUSTOM_DIR}/repodata/*-comps.xml ${ISO_CUSTOM_DIR}/repodata/comps.xml
     createrepo -q -g repodata/comps.xml ${ISO_CUSTOM_DIR}
  fi
}

function prepare_workdir() {
  download_official_iso

  show_msg "Copying the ISO files ..."
  if [ $(grep ${ISO_MOUNT_DIR} /proc/mounts) ]; then
    umount ${ISO_MOUNT_DIR}
  fi

  rm -rf ${ISO_MOUNT_DIR}
  rm -rf ${ISO_CUSTOM_DIR}

  mkdir -p ${ISO_MOUNT_DIR}
  mkdir -p ${ISO_CUSTOM_DIR}

  # copy ISO content
  mount -o loop -r ${OFFICIAL_ISO} ${ISO_MOUNT_DIR}
  rsync -Pazq --exclude=TRANS.TBL ${ISO_MOUNT_DIR}/ ${ISO_CUSTOM_DIR}
  umount ${ISO_MOUNT_DIR}
  rm -rf ${ISO_MOUNT_DIR}
}

function iso_customize() {
  prepare_workdir

  copy_custom_config
  copy_custom_files

  copy_custom_rpms
}

function iso_create() {
  show_msg "Creating ${TARGET_ISO} ..."
  genisoimage -quiet              \
    -U                            \
    -T                            \
    -r                            \
    -A "${ISO_LABEL}"             \
    -V "${ISO_LABEL}"             \
    -volset "${ISO_LABEL}"        \
    -p "User <email@some.com>"    \
    -J -joliet-long               \
    -l                            \
    -b isolinux/isolinux.bin      \
    -c isolinux/boot.cat          \
    -no-emul-boot                 \
    -boot-info-table              \
    -boot-load-size 4             \
    -x "lost+found"               \
    -eltorito-alt-boot            \
    -e images/efiboot.img         \
    -no-emul-boot                 \
    -o ${TARGET_ISO}              \
    ${ISO_CUSTOM_DIR}
  
  show_msg "Post-processing ${TARGET_ISO} to allow hybrid booting ..."
  isohybrid ${TARGET_ISO}

  show_msg "Implanting MD5 into ${TARGET_ISO} ..."
  implantisomd5 ${TARGET_ISO}
  
  show_msg "Done !!!"
}

function iso_install() {
  if [ "${START_MODE}" == "uefi" ] ; then
    VM_NAME="${VM_NAME}-uefi"
    VNC_PORT=${VNC_PORT_UEFI}
    BOOT="--boot uefi"
  else
    VNC_PORT=${VNC_PORT_BIOS}
    BOOT=""
  fi

  show_msg "Deleting old instance in kvm ..."
  virsh destroy  ${VM_NAME}         &> /dev/null || true
  virsh undefine ${VM_NAME} --nvram &> /dev/null || true

  show_msg "Creating virtual disk ..."
  rm -f ${VM_NAME}.qcow2
  qemu-img create -f qcow2 ${VM_NAME}.qcow2 40G > /dev/null

  show_msg "Installing ISO(${START_MODE})(VNC port: ${VNC_PORT}) ..."
  virt-install --virt-type kvm ${BOOT} \
    --name ${VM_NAME}                  \
    --os-type='linux'                  \
    --os-variant='rhel7'               \
    --vcpus=${VM_CPU} --ram ${VM_RAM}  \
    --cdrom=${TARGET_ISO}              \
    --disk path=${VM_NAME}.qcow2       \
    --network=bridge:virbr0,model=virtio,driver_name=vhost,driver_queues=${VM_CPU} \
    --console pty,target_type=virtio \
    --graphics vnc,port=${VNC_PORT},listen=0.0.0.0,keymap=en-us \
    --accelerate --noautoconsole

  show_msg "Waiting for the installation to complete ..."
  while true ; do
    DOMAINSTS=`LANG=C virsh domstate ${VM_NAME}`
    if [ "${DOMAINSTS}" == "shut off" ] ; then
      break
    else
      echo -n "."
      sleep 10
    fi
  done
  echo -e "\n"

  #show_msg "Reseting the virtual machine ..."
  #virt-sysprep -a ${TOPDIR}/${VM_NAME}.qcow2 --format qcow2 --no-network

  #show_msg "Compressing the qcow2 image ..."
  #QCOW2_NAME=$(sed 's#iso#qcow2#' ${TARGET_ISO})
  #qemu-img convert -c -O qcow2 ${VM_NAME}.qcow2 ${QCOW2_NAME}

  show_msg "Installing Done !"
}

function iso_run() {
  if [ "${START_MODE}" == "uefi" ] ; then
    VM_NAME="${VM_NAME}-uefi"
  fi
  
  show_msg "Staring ${VM_NAME}(${START_MODE}) ..."
  virsh start   ${VM_NAME}
  #virsh console ${VM_NAME}
}
##########################################################
FLAG_CREATE=false
FLAG_ONLYCREATE=false
FLAG_INSTALL=false
FLAG_RUN=false


function help() {

  cat << EOF
$(tput bold)USAGE$(tput sgr0):
  $0 [-c|-o] [-i] [-r] [-u] [-p]

$(tput bold)OPTIONS$(tput sgr0):
  -$(tput bold)c$(tput sgr0)
  --create
      Create the new ISO file.
  -$(tput bold)o$(tput sgr0)
  --onlycreate
      Create the new ISO file, but no prepare works(done before).
      Just to save some time.
  -$(tput bold)i$(tput sgr0)
  --install
      Install a virtual machine using the ISO generated before.
        Need install KVM.
  -$(tput bold)r$(tput sgr0)
  --run
      Start the installed virtual machine.
  -$(tput bold)u$(tput sgr0)
  --uefi
      Install the ISO with UEFI mode, default is BIOS mode.
      This option work with -r and -i options.
      Need install OVMF.
  -$(tput bold)p$(tput sgr0) <port>
  --vncport <port>
      VNC port number.
  -$(tput bold)h$(tput sgr0)
  --help
      Display this help.

$(tput bold)EXAMPLES$(tput sgr0):
  $0 -c              # generate the customized ISO
  $0 -i              # Use KVM to install the ISO(BIOS mode), default VNC port=5936
  $0 -i -u -p 5940   # Use KVM to install the ISO(UEFI mode), VNC port=5940
  $0 -r              # Start the installed virtual machine(BISO) just created.
  $0 -r -u           # Start the installed virtual machine(UEFI) just created.
  $0 -c -i -r        # create/install/run
EOF
  exit 1
}

function main() {
  while [ -n "$1" ] ; do
    case "$1" in
    "-c"|"--create")
        FLAG_CREATE=true
        shift 1
        ;;
    "-o"|"--onlycreate")
        FLAG_ONLYCREATE=true
        shift 1
        ;;
    "-i"|"--install")
        FLAG_INSTALL=true
        shift 1
        ;;
    "-r"|"--run")
        FLAG_RUN=true
        shift 1
        ;;
    "-u"|"--uefi")
        START_MODE="uefi"
        shift 1
        ;;
    "-p"|"--vncport")
        if [ -n "$2" ]; then
          SPEC_PORT="$2"
          shift 2
        else
          help
        fi
        ;;
    "-h"|"--help")
        help
        ;;
    *)
        help
    esac
  done

  if ${FLAG_ONLYCREATE} ; then
    if ${FLAG_CREATE} ; then
        help
    else
        iso_create
    fi
  fi

  if ${FLAG_CREATE} ; then
    iso_customize
    iso_create
  fi

  # VNC port setting
  if [ ! -z "${SPEC_PORT}" ] ; then
    if [ "${START_MODE}" == "uefi" ] ; then
      VNC_PORT_UEFI="${SPEC_PORT}"
    else
      VNC_PORT_BIOS="${SPEC_PORT}"
    fi
  fi

  if ${FLAG_INSTALL} ; then
    iso_install
  fi

  if ${FLAG_RUN} ; then
    iso_run
  fi
}

main "$@"