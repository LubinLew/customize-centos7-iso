# customize centos7 iso

This project aims to create a customized CentOS 7 ISO image with kickstart to automate the installation process.

## Usage

```txt
USAGE:
  ./build.sh [-c|-o] [-i] [-r] [-u] [-p]

OPTIONS:
  -c
  --create
      Create the new ISO file.
  -o
  --onlycreate
      Create the new ISO file, but no prepare works(done before).
      Just to save some time.
  -i
  --install
      Install a virtual machine using the ISO generated before.
      Need install KVM.
  -r
  --run
      Start the installed virtual machine.
  -u
  --uefi
      Install the ISO with UEFI mode, default is BIOS mode.
      This option work with -r and -i options.
      Need install OVMF.
  -p <port>
  --vncport <port>
      VNC port number.

EXAMPLES:
  ./build.sh -c              # generate the customized ISO
  ./build.sh -i              # Use KVM to install the ISO(BIOS mode), default VNC port=5936
  ./build.sh -i -u -p 5940   # Use KVM to install the ISO(UEFI mode), VNC port=5940
  ./build.sh -r              # Start the installed virtual machine(BISO) just created.
  ./build.sh -r -u           # Start the installed virtual machine(UEFI) just created.
  ./build.sh -c -i -r        # create/install/run
```

## Setup

**Basic**

```bash
yum install -y genisoimage syslinux isomd5sum createrepo rsync
```

| CMD           | Description                                                                                                                |
| ------------- | -------------------------------------------------------------------------------------------------------------------------- |
| genisoimage   | create ISO file                                                                                                            |
| implantisomd5 | implant an MD5 checksum in an ISO9660 image                                                                                |
| checkisomd5   | check an MD5 checksum implanted by implantisomd5                                                                           |
| isohybrid     | Post-process an ISO 9660 image generated with mkisofs or genisoimage to allow hybrid booting as a CD-ROM or as a hard disk |
| createrepo    | Create repomd (xml-rpm-metadata) repository                                                                                |

> `mkisofs` and `genisoimage`
> 
> `genisoimage` is part of [cdrkit](https://en.wikipedia.org/wiki/Cdrkit), while `mkisofs` is part of [cdrtools](https://en.wikipedia.org/wiki/Cdrtools).
> 
> cdrkit was created in 2006 by Debian developers as a fork of cdrtools based on the last GPL-licensed version when cdrtools licensing changed. 
> 
> in CentOS7 `mkisofs` is a symbolic link to `genisoimage`.



**KVM**(Optional)

```bash
yum install -y qemu-kvm qemu-kvm-tools libvirt virt-install libguestfs-tools

systemctl start  libvirtd
systemctl enable libvirtd
```



**OVMF**(Optional)

```bash
# https://www.server-world.info/en/note?os=CentOS_7&p=kvm&f=11

cat > /etc/yum.repos.d/kraxel.repo << EOF
[qemu-firmware-jenkins]
name=firmware for qemu, built by jenkins, fresh from git repos
baseurl=https://www.kraxel.org/repos/jenkins/
enabled=0
gpgcheck=0
EOF
yum --enablerepo=qemu-firmware-jenkins -y install OVMF edk2.git-ovmf-x64
cat >> /etc/libvirt/qemu.conf << EOF
nvram = [
    "/usr/share/edk2.git/ovmf-x64/OVMF_CODE-pure-efi.fd:/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd",
]
EOF

# update qemu
yum -y install centos-release-qemu-ev
yum --enablerepo=centos-qemu-ev -y install qemu-kvm-ev

systemctl restart libvirtd
```

----

## References

https://github.com/fabaff/make_centos

https://github.com/CentOS/sig-core-livemedia

https://github.com/CentOS/Community-Kickstarts
