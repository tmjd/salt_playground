#!/bin/bash

function init_ssh_host
{
    if [ $# -ne 1 ]; then
        echo "No arg passed to init_ssh_host"
        exit 1
    fi
    local host=$1
    ssh-keygen -R $host
    echo -n "SSH init $host: "
    ssh -o StrictHostKeyChecking=no root@$host 'uname -a'
    return $?
}

cd "$(dirname $0)"

if [ $# -eq 0 ]; then
    echo "no hosts specified nothing to do"
    exit 1
fi


trap finish EXIT

master=$1
shift
echo "Initializing salt master $master"
init_ssh_host $master
if [ $? -ne 0 ]; then
    echo "Failed initializing ssh to master"
    cat $tmp_file
    exit
fi

rm -f init.sh
cat > init.sh <<- EOT
#!/bin/bash -x
tmp_file=\$(mktemp)
function finish
{
    rm -f \$tmp_file
}
echo 'America/Chicago' > /etc/timezone
add-apt-repository --yes ppa:saltstack/salt
echo "Updating apt"
apt-get update &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed:"; cat \$tmp_file; fi
apt-get install --yes salt-master &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed:"; cat \$tmp_file; fi
EOT
scp init.sh root@$master:/root/
ssh root@$master 'bash /root/init.sh'
if [ $? -ne 0 ]; then echo "Failed running init on master"; exit; fi
scp pre_salt/salt_master.conf root@$master:/etc/salt/master
if [ $? -ne 0 ]; then echo "Failed coping over salt master"; exit; fi
scp -r srv/* root@$master:/srv/
if [ $? -ne 0 ]; then echo "Failed copying salt info to master"; exit; fi
ssh root@$master 'systemctl start salt-master'
if [ $? -ne 0 ]; then echo "Failed starting salt-master"; exit; fi

rm -f init.sh
cat > init.sh <<- EOT
#!/bin/bash -x
tmp_file=\$(mktemp)
function finish
{
    rm -f \$tmp_file
}
echo 'America/Chicago' > /etc/timezone
add-apt-repository --yes ppa:saltstack/salt
apt-get update &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed:"; cat \$tmp_file; fi
apt-get install --yes salt-minion &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed:"; cat \$tmp_file; fi
echo '$(getent hosts saltmaster | awk '{ print $1 }') salt' >> /etc/hosts
systemctl start salt-minion
EOT

while [ $# -ne 0 ]; do
    host=$1
    shift
    echo "Initializing minion $host"
    init_ssh_host $host
    if [ $? -ne 0 ]; then echo 'Failed init of minion $host'; continue; fi

    scp init.sh root@$host:/root/
    ssh root@$host 'bash /root/init.sh'
    if [ $? -ne 0 ]; then echo 'Failed running init on $host'; continue; fi

    ssh root@$master "salt-key -a $host -y"
done

echo "done"
