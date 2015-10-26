#!/bin/bash

tmp_file=$(mktemp)
function finish
{
    rm -f $tmp_file
}
trap finish EXIT

function init_ssh_host
{
    if [ $# -ne 1 ]; then
        echo "No arg passed to init_ssh_host"
        exit 1
    fi
    local host=$1
    ssh-keygen -R $host &> $tmp_file
    if [ $? -ne 0 ]; then
        echo "Failed removing key $host"; cat $tmp_file; return 1;
    fi
    ssh -o StrictHostKeyChecking=no root@$host 'uname -a' &> $tmp_file
    if [ $? -ne 0 ]; then
        echo "Failed initial login to $host"; cat $tmp_file; return 1;
    fi
    return $?
}

cd "$(dirname $0)"

#Has DO_PAT and SSH_FINGERPRINT defined
source ./private.sh

if [ $# -eq 0 ]; then
    echo "no hosts specified nothing to do"
    exit 1
elif [ "$1" == "-d" -o "$1" == "--destroy" ]; then
    terraform plan -destroy -out=destroy_plan.tfplan \
        -var "do_token=${DO_PAT}" \
        -var "pub_key=$HOME/.ssh/id_rsa.pub" \
        -var "pvt_key=$HOME/.ssh/id_rsa" \
        -var "ssh_fingerprint=$SSH_FINGERPRINT" \
        ./infrastructure/ &> $tmp_file
    if [ $? -ne 0 ]; then
        echo "Failed planning terraform destroy"
        cat $tmp_file
        exit 1
    fi

    terraform apply destroy_plan.tfplan &> $tmp_file
    if [ $? -eq 0 ]; then
        rm -f destroy_plan.tfplan
    else
        echo "Failed implementing terraform destroy"
        cat $tmp_file
        exit 1
    fi
    exit 0
fi

#Prompt for sudo password so it doesn't have to happen later
sudo --validate

master=$1
shift
minions=""
while [ $# -ne 0 ]; do
    minions="$minions$1 "
    shift
done

echo "Master: $master"
echo "Minions: $minions"

#Cleanup then create the minion terraform files
rm -f infrastructure/minion_*.tf
for minion in $minions; do
    sed -e "s/minion_name/$minion/" infrastructure/minion.template \
        > infrastructure/minion_$minion.tf
done

echo "Implimenting terraform"
terraform apply \
    -var "do_token=${DO_PAT}" \
    -var "pub_key=$HOME/.ssh/id_rsa.pub" \
    -var "pvt_key=$HOME/.ssh/id_rsa" \
    -var "ssh_fingerprint=$SSH_FINGERPRINT" \
    ./infrastructure/ &> $tmp_file
if [ $? -ne 0 ]; then echo "Failed terraform step"; cat $tmp_file; fi

ipv4_address=""
name=""
while read -r line; do
    if [[ "$line" =~ digitalocean ]]; then
        sudo sed -i -e "/.*$name.*/d" /etc/hosts
        echo "$ipv4_address $name" | sudo tee -a /etc/hosts
    elif [[ "$line" =~ name\ = ]]; then
        name=$(echo "$line" | sed -e 's/^.*= *//')
    elif [[ "$line" =~ ipv4_address ]]; then
        ipv4_address=$(echo "$line" | sed -e 's/^.*= *//')
    else
        /bin/true
    fi
done < <(terraform show | tac; echo '')

echo "== Initializing salt master $master =="
init_ssh_host $master &> $tmp_file
if [ $? -ne 0 ]; then
    echo "Failed initializing ssh to master"
    cat $tmp_file
    exit
fi

rm -f init.sh
cat > init.sh <<- EOT
#!/bin/bash
tmp_file=\$(mktemp)
function finish
{
    rm -f \$tmp_file
}
trap finish EXIT
echo 'America/Chicago' > /etc/timezone
apt-get install --yes screen vim &> \$tmp_file
if [ \$? -ne 0 ]; then
    echo "Failed installing screen and vim:"
    cat \$tmp_file
    exit 1
fi
echo "  Adding salt repo"
add-apt-repository --yes ppa:saltstack/salt &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed ppa add:"; cat \$tmp_file; exit 1; fi
echo "  Updating apt \$(hostname)"
apt-get update &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed apt update:"; cat \$tmp_file; exit 1; fi
echo "  Installing salt-master"
apt-get install --yes salt-master &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed install master:"; cat \$tmp_file; exit 1; fi
EOT
scp init.sh root@$master:/root/ >/dev/null
ssh root@$master 'bash /root/init.sh'
if [ $? -ne 0 ]; then echo "Failed running init on master"; exit; fi
scp pre_salt/salt_master.conf root@$master:/etc/salt/master >/dev/null
if [ $? -ne 0 ]; then echo "Failed coping over salt master"; exit; fi
scp -r srv/* root@$master:/srv/ >/dev/null
if [ $? -ne 0 ]; then echo "Failed copying salt info to master"; exit; fi
ssh root@$master 'systemctl start salt-master'
if [ $? -ne 0 ]; then echo "Failed starting salt-master"; exit; fi

rm -f init.sh
cat > init.sh <<- EOT
#!/bin/bash
tmp_file=\$(mktemp)
function finish
{
    rm -f \$tmp_file
}
trap finish EXIT
echo 'America/Chicago' > /etc/timezone
echo "  Adding salt repo"
add-apt-repository --yes ppa:saltstack/salt &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed ppa add:"; cat \$tmp_file; exit 1; fi
echo "  Updating apt \$(hostname -s)"
apt-get update &> \$tmp_file
if [ \$? -ne 0 ]; then echo "Failed apt update:"; cat \$tmp_file; exit 1; fi
echo "  Installing salt-minion \$(hostname)"
apt-get install --yes salt-minion &> \$tmp_file
if [ \$? -ne 0 ]; then
    echo "Failed install of salt-minion trying again";
    apt-get install --yes salt-minion &> \$tmp_file
    if [ \$? -ne 0 ]; then
        echo "Failed retry of install of salt-minion";
        cat \$tmp_file;
        exit 1;
    fi
fi
echo '$(getent hosts saltmaster | awk '{ print $1 }') salt' >> /etc/hosts
systemctl start salt-minion
EOT

for minion in $minions; do
    echo "== Initializing minion $minion =="
    init_ssh_host $minion
    if [ $? -ne 0 ]; then echo "Failed init of minion $minion"; continue; fi

    scp init.sh root@$minion:/root/ >/dev/null
    ssh root@$minion 'bash /root/init.sh'
    if [ $? -ne 0 ]; then echo "Failed running init on $minion"; continue; fi
done

echo "sleep for 10 to let all minions connect"
sleep 10

for minion in $minions; do
    ssh root@$master "salt-key -a $minion -y" &> $tmp_file
    if [ $? -ne 0 ]; then echo "Failed accepting $minion"; continue; fi
    echo "Accepted minion $minion"
done

sleep 5
ssh root@$master "salt '*' state.highstate"
if [ $? -ne 0 ]; then
    echo "##==> Failed bringing up highstate <==##"
fi


echo "done"
