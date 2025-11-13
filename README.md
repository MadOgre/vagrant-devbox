# vagrant-devbox
An OS-agnostic development environment for collaboration

## The following is a list of steps to jump start your collaboration on Product Feedback App (https://github.com/MadOgre/product-feedback-app-2)

1. Install VirtualBox for your operating system (https://www.virtualbox.org/wiki/Downloads)

2. Install Vagrant (https://developer.hashicorp.com/vagrant/install)

3. Clone this repository to a suitable folder
```
   git clone git@github.com:MadOgre/vagrant-devbox.git
```
4. (optional) if you use ssh key to access your GitHub account, copy both private and public key into keys subfolder inside devbox
   
5. (optional) copy the `Vagrantfile.local.sample` into `Vagrantfile.local` - you may change number of cpus and memory or add custom mount points

5. run `vagrant up` - this will perform provisioning, install the keys if present, then clone the main code repository into `/home/vagrant/code`, and run all the necessary scripts such as `pnpm install`

6. Wait for provisioning to complete

7. Run commands to configure git
```
   git config --global user.email "myemail@example.com"
   git config --global user.name "John Collaborator"
```

8. Run `vagrant ssh` to connect to the machine

9. Serve the repository locally by running `vite run dev`

10. Configure VSCode to connect to `/home/vagrant/code` folder on the virtual server by using **Remote - SSH** extension by Microsoft

