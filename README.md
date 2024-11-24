# HomeLab
A repo with my HomeLab config.

For anyone who cares how it works:
1. Hyper-V Server 2019 is currently the hypervisor being used. The user should install this on their machine.
2. Once installed, the user can use the provided Packer configs to build their images. The images require a public key for the main user logon as well as a private/public key pair for the Ansible user. Ansible is used to provision the machines as well as provide a way to update all machines.
3. PowerForm is used to build VMs from the images. See the PowerForm repo for more info: github.com/savdagod/powerformforhyperv

