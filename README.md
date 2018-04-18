# SynfulAnsible
VERY Simple Ansible configuration for provisioning a server with the Synful PHP Framework.
Synful: https://github.com/nathan-fiscaletti/synful
### Steps:

Clone repo to desired location.

Edit synful.yml and insert your desired MySQL password.

Make sure your desired host has your public key in it's authorized_users file.

NOTE: For this process, you must be able to access your machine via SSH as the ROOT user.

Run the commands:

```ssh-agent bash```

```ssh-add path/to/private/key```

For Ansible to work, the host machine must have python installed. If it does not, you can install it remotely using:

```ssh root@<IP> "apt-get install python -y"```

Once you can log into the machine as root without specifying a key file, in the root repo directory, you can run:

```ansible-playbook -i <IP of Host>, synful.yml -u root```
