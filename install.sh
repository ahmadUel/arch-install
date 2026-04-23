#!/usr/bin/env bash
# =============================================================================
# Arch Linux Automated Installer
# Single ext4 partition · No DE · Intel CPU + iGPU
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[*]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[✓]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[!]${RESET} $*"; }
die()     { echo -e "${RED}${BOLD}[✗]${RESET} $*"; exit 1; }

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Run as root (you should be in the live ISO)"
ping -c 1 -W 3 archlinux.org &>/dev/null || die "No internet connection"

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}"
cat <<'EOF'
  █████╗ ██████╗  ██████╗██╗  ██╗    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
 ██╔══██╗██╔══██╗██╔════╝██║  ██║    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
 ███████║██████╔╝██║     ███████║    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
 ██╔══██║██╔══██╗██║     ██╔══██║    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
 ██║  ██║██║  ██║╚██████╗██║  ██║    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
 ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
EOF
echo -e "${RESET}"
echo -e "  ${CYAN}Single ext4 · No DE · Intel CPU/iGPU${RESET}\n"

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 1 — GATHER USER INPUT
# ═════════════════════════════════════════════════════════════════════════════

# ── Disk ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Available disks:${RESET}"
lsblk -dpno NAME,SIZE,MODEL | grep -v "loop\|sr0"
echo
read -rp "$(echo -e "${BOLD}Target disk${RESET} (e.g. /dev/sda): ")" DISK
[[ -b "$DISK" ]] || die "Disk $DISK not found"

# ── Boot mode ─────────────────────────────────────────────────────────────────
if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="uefi"
    info "Boot mode: UEFI detected"
else
    BOOT_MODE="bios"
    info "Boot mode: BIOS/Legacy detected"
fi

# ── Hostname ──────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Hostname${RESET}: ")" HOSTNAME
[[ -n "$HOSTNAME" ]] || die "Hostname cannot be empty"

# ── Username ──────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Username${RESET}: ")" USERNAME
[[ -n "$USERNAME" ]] || die "Username cannot be empty"

# ── Passwords ─────────────────────────────────────────────────────────────────
read -srp "$(echo -e "${BOLD}Root password${RESET}: ")" ROOT_PASS; echo
read -srp "$(echo -e "${BOLD}Confirm root password${RESET}: ")" ROOT_PASS2; echo
[[ "$ROOT_PASS" == "$ROOT_PASS2" ]] || die "Root passwords do not match"

read -srp "$(echo -e "${BOLD}Password for ${USERNAME}${RESET}: ")" USER_PASS; echo
read -srp "$(echo -e "${BOLD}Confirm password for ${USERNAME}${RESET}: ")" USER_PASS2; echo
[[ "$USER_PASS" == "$USER_PASS2" ]] || die "User passwords do not match"

# ── Timezone ──────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Timezone${RESET} (e.g. Africa/Cairo): ")" TIMEZONE
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Invalid timezone: $TIMEZONE"

# ── Locale ────────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Locale${RESET} [default: en_US.UTF-8]: ")" LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"

# ── Keymap ────────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Keymap${RESET} [default: us]: ")" KEYMAP
KEYMAP="${KEYMAP:-us}"

# ── Swap file ─────────────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Swap file size in GB${RESET} (0 to skip): ")" SWAP_SIZE
SWAP_SIZE="${SWAP_SIZE:-0}"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}════════════ Summary ════════════${RESET}"
echo -e "  Disk:      ${RED}${BOLD}$DISK — THIS WILL BE WIPED${RESET}"
echo -e "  Boot mode: $BOOT_MODE"
echo -e "  Hostname:  $HOSTNAME"
echo -e "  User:      $USERNAME"
echo -e "  Timezone:  $TIMEZONE"
echo -e "  Locale:    $LOCALE"
echo -e "  Keymap:    $KEYMAP"
echo -e "  Swap:      ${SWAP_SIZE}G"
echo -e "${BOLD}═════════════════════════════════${RESET}"
echo
read -rp "$(echo -e "${RED}${BOLD}Proceed? All data on $DISK will be destroyed. [yes/N]: ${RESET}")" CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted."

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 2 — PARTITION + FORMAT
# ═════════════════════════════════════════════════════════════════════════════

info "Wiping disk $DISK..."
wipefs -a "$DISK" &>/dev/null
sgdisk -Z "$DISK" &>/dev/null || true

if [[ "$BOOT_MODE" == "uefi" ]]; then
    info "Creating GPT partition table (EFI + root)..."
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI"  "$DISK"
    sgdisk -n 2:0:0      -t 2:8300 -c 2:"root" "$DISK"

    # Derive partition names (handles nvme0n1p1 vs sda1)
    if [[ "$DISK" =~ nvme ]]; then
        EFI_PART="${DISK}p1"
        ROOT_PART="${DISK}p2"
    else
        EFI_PART="${DISK}1"
        ROOT_PART="${DISK}2"
    fi

    info "Formatting EFI partition..."
    mkfs.fat -F32 -n EFI "$EFI_PART"

    info "Formatting root partition as ext4..."
    mkfs.ext4 -L root "$ROOT_PART"

    info "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mount --mkdir "$EFI_PART" /mnt/boot

else
    info "Creating MBR partition table (single root)..."
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary ext4 1MiB 100%
    parted -s "$DISK" set 1 boot on

    if [[ "$DISK" =~ nvme ]]; then
        ROOT_PART="${DISK}p1"
    else
        ROOT_PART="${DISK}1"
    fi

    info "Formatting root partition as ext4..."
    mkfs.ext4 -L root "$ROOT_PART"

    info "Mounting root partition..."
    mount "$ROOT_PART" /mnt
fi

success "Partitioning done"

# ── Swap file ─────────────────────────────────────────────────────────────────
if [[ "$SWAP_SIZE" -gt 0 ]]; then
    info "Creating ${SWAP_SIZE}G swap file..."
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$(( SWAP_SIZE * 1024 )) status=progress
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
    success "Swap file created"
fi

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 3 — BASE INSTALL
# ═════════════════════════════════════════════════════════════════════════════

info "Updating pacman mirrors..."
reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || \
    warn "reflector failed, using default mirrors"

info "Installing base system (this will take a while)..."
pacstrap -K /mnt \
    base base-devel \
    linux linux-firmware linux-headers \
    intel-ucode \
    networkmanager \
    sudo \
    nano neovim \
    git \
    htop btop \
    man-db man-pages \
    bash-completion \
    mesa libva-intel-driver intel-media-driver vulkan-intel libva-utils \
    pipewire pipewire-pulse wireplumber \
    tmux \
    curl wget \
    zip unzip \
    which

success "Base system installed"

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 4 — FSTAB
# ═════════════════════════════════════════════════════════════════════════════

info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

if [[ "$SWAP_SIZE" -gt 0 ]]; then
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
fi

success "fstab written"

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 5 — CHROOT CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

info "Configuring system inside chroot..."

arch-chroot /mnt /bin/bash -s "$TIMEZONE" "$LOCALE" "$KEYMAP" "$HOSTNAME" \
    "$ROOT_PASS" "$USERNAME" "$USER_PASS" "$BOOT_MODE" "$DISK" \
    <<'CHROOT'

TIMEZONE="$1"; LOCALE="$2"; KEYMAP="$3"; HOSTNAME="$4"
ROOT_PASS="$5"; USERNAME="$6"; USER_PASS="$7"
BOOT_MODE="$8"; DISK="$9"

# ── Timezone ──────────────────────────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ── Locale ────────────────────────────────────────────────────────────────────
sed -i "s/^#\(${LOCALE}\)/\1/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# ── Keymap ────────────────────────────────────────────────────────────────────
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# ── Hostname ──────────────────────────────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ── Root password ─────────────────────────────────────────────────────────────
echo "root:${ROOT_PASS}" | chpasswd

# ── User ──────────────────────────────────────────────────────────────────────
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Enable sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ── NetworkManager ────────────────────────────────────────────────────────────
systemctl enable NetworkManager

# ── Pipewire ──────────────────────────────────────────────────────────────────
systemctl --global enable pipewire pipewire-pulse wireplumber

# ── mkinitcpio ────────────────────────────────────────────────────────────────
mkinitcpio -P

# ── Bootloader ────────────────────────────────────────────────────────────────
if [[ "$BOOT_MODE" == "uefi" ]]; then
    bootctl install

    cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor  no
EOF

    # Get UUID of root partition (label "root")
    ROOT_UUID=$(blkid -s UUID -o value LABEL=root)

    cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw quiet
EOF

    cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux-fallback.img
options root=UUID=${ROOT_UUID} rw
EOF

else
    # BIOS — GRUB
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$DISK"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

CHROOT

success "Chroot configuration complete"

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 6 — DONE
# ═════════════════════════════════════════════════════════════════════════════

echo
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}   Installation complete!               ${RESET}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "  Reboot with: ${BOLD}reboot${RESET}"
echo -e "  Remove the USB when the screen goes blank."
echo
