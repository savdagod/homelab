variable "image_name" {
  type = string
  default = "img-base"
}

variable "hostname" {
  type = string
  default = "base-vm"
}

variable "bjt" {
  type = map(string)
}

variable "ansible" {
  type = map(string)
}

variable "packer" {
  type = map(string)
}

variable "iso_checksum" {}
variable "iso_url" {}

source "hyperv-iso" "debian" {
  vm_name            = "${var.hostname}"
  cpus               = 4
  memory             = 2048
  disk_size          = 20480
  switch_name        = "Default Switch"
  enable_secure_boot = false
  generation         = 2
  headless           = true
  configuration_version = "9.0"
  http_directory     = "http"
  iso_checksum       = "${var.iso_checksum}"
  iso_url            = "${var.iso_url}"
  output_directory   = "debian-${var.image_name}"
  communicator       = "ssh"
  ssh_username       = "${var.packer.name}"
  ssh_password       = "${var.packer.password}"
  boot_command       = ["<wait>c<wait>", 
                      "linux /install.amd/vmlinuz ", 
                      "auto=true ",
                      "netcfg/disable_autoconfig=true ",
                      "netcfg/get_ipaddress=172.16.0.100 ",
                      "netcfg/get_netmask=255.255.255.0 ",
                      "netcfg/get_gateway=172.16.0.1 ",
                      "netcfg/get_nameservers=8.8.8.8 ",
                      "netcfg/confirm_static=true ",
                      "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}//${var.image_name}.cfg ", 
                      "hostname=${var.hostname} ", 
                      "domain=template.local ", 
                      "interface=auto ", 
                      "vga=788 noprompt quiet --<enter>", 
                      "initrd /install.amd/initrd.gz<enter>", 
                      "boot<enter>"]
  ssh_timeout        = "10m"
  shutdown_command   = "echo ${var.packer.password} | sudo -S shutdown -P now"
}

build {
  sources = ["source.hyperv-iso.debian"]

  provisioner "file" {
    sources = ["./keys/${var.ansible.key}","./keys/${var.bjt.key}"]
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "echo '${var.packer.password}' | sudo -S useradd -s /bin/bash -m ${var.bjt.name}",
      "echo '${var.packer.password}' | sudo -S sh -c \"echo '${var.bjt.name}:${var.bjt.password}' | chpasswd\"",
      "echo '${var.packer.password}' | sudo -S usermod -aG sudo ${var.bjt.name}",
      "echo '${var.packer.password}' | sudo -S mkdir -p /home/${var.bjt.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S mv /tmp/${var.bjt.key} /home/${var.bjt.name}/.ssh/authorized_keys",
      "echo '${var.packer.password}' | sudo -S chown -R ${var.bjt.name}:${var.bjt.name} /home/${var.bjt.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S chmod 700 /home/${var.bjt.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S chmod 600 /home/${var.bjt.name}/.ssh/authorized_keys",
      "echo '${var.packer.password}' | sudo -S useradd -s /bin/bash -m ${var.ansible.name}",
      "echo '${var.packer.password}' | sudo -S sh -c \"echo '${var.ansible.name}:${var.ansible.password}' | chpasswd\"",
      "echo '${var.packer.password}' | sudo -S usermod -aG sudo ${var.ansible.name}",
      "echo '${var.packer.password}' | sudo -S mkdir -p /home/${var.ansible.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S mv /tmp/${var.ansible.key} /home/${var.ansible.name}/.ssh/authorized_keys",
      "echo '${var.packer.password}' | sudo -S chown -R ${var.ansible.name}:${var.ansible.name} /home/${var.ansible.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S chmod 700 /home/${var.ansible.name}/.ssh",
      "echo '${var.packer.password}' | sudo -S chmod 600 /home/${var.ansible.name}/.ssh/authorized_keys",
      "echo '${var.packer.password}' | sudo -S sh -c \"echo 'PasswordAuthentication no' | tee -a /etc/ssh/sshd_config > /dev/null\"",
      "echo '${var.packer.password}' | sudo -S sh -c \"echo 'ChallengeResponseAuthentication no' | tee -a /etc/ssh/sshd_config > /dev/null\"",
      "echo '${var.packer.password}' | sudo -S apt update && echo '${var.packer.password}' | sudo -S apt install python3 -y",
      "echo '${var.packer.password}' | sudo -S sh -c \"sed -i 's/iface eth0 inet static/iface eth0 inet dhcp/' /etc/network/interfaces\""
    ]
  }
}



