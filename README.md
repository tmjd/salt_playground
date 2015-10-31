To use this playground you need a DigitalOcean(DO) account, SSH keys setup on
DO, and a DO Personal Access Token.

To run setup.sh
---------------

0. Create a private.sh in the same folder as this README
    * Add `export DO_PAT="<your personal access token goes here>"`
    * Add `export SSH_FINGERPRINT="<DO ssh fingerprint goes here>"`
        * I found this by going to the API page and looking at the page source and found the fingerprint there, it was a 7 digit number
0. Now you're ready to run setup.sh 

Running setup.sh
----------------

* Create and start VMs and create a salt master and minions the master will manage
    * `./setup.sh saltmaster minion1 zoominion1 zoominion2`
    * For each 'name' specified after setup.sh the script will startup a VM that will have the specified name.
    * The first name will be used for the saltmaster
    * Each subsequent name after the first will be another minion that the saltmaster will manage
    * If a minion's name starts with zoo then it will be put into the zookeeper cluster
* Destroy everything the above command created on DO
    * `./setup.sh --destroy`

