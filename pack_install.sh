#!/bin/bash

ifconfig
read -p "Enter your external interface: " EXT_INTER

# do not edit after this line
set -x   # enable echo

sudo yum install -y epel-release
sudo yum install -y vim git tmux bash-completion net-tools htop psmisc
sudo yum install -y centos-release-openstack-newton
sudo yum update -y
sudo yum install -y openstack-packstack

sudo systemctl disable firewalld
sudo systemctl stop firewalld
sudo systemctl disable NetworkManager
sudo systemctl stop NetworkManager
sudo systemctl enable networ
sudo systemctl start network

curl -L bit.do/ltmux | sudo tee /usr/bin/ltmux
sudo chmod a+x /usr/bin/ltmux

# temporary workaround
wget https://buildlogs.centos.org/centos/7/cloud/x86_64/openstack-newton/common/python2-tinyrpc-0.5-2.el7.noarch.rpm
sudo yum --nogpgcheck localinstall -y python2-tinyrpc-0.5-2.el7.noarch.rpm
rm python2-tinyrpc-0.5-2.el7.noarch.rpm
# end temporary workaround

echo -e '\a' # beep

sudo packstack \
    --allinone \
    --provision-demo=n \
    --os-neutron-ovs-bridge-mappings=extnet:br-ex \
    --os-neutron-ovs-bridge-interfaces=br-ex:$EXT_INTERFACE \
    --os-neutron-ml2-type-drivers=vxlan,flat

echo -e '\a' # beep

# fix kvm
sudo rmmod kvm_intel
sudo rmmod kvm
sudo modprobe kvm
sudo modprobe kvm_intel

# network configuration (https://www.rdoproject.org/networking/neutron-with-existing-external-network/)
sudo tee /etc/sysconfig/network-scripts/ifcfg-br-ex <<EOF
DEVICE=br-ex
DEVICETYPE=ovs
TYPE=OVSBridge
BOOTPROTO=static
IPADDR=192.168.122.212 # Old $EXT_INTERFACE IP since we want the network restart to not 
                       # kill the connection, otherwise pick something outside your dhcp range
NETMASK=255.255.255.0  # your netmask
GATEWAY=192.168.122.1  # your gateway
DNS1=192.168.122.1     # your nameserver
ONBOOT=yes
EOF

sudo tee /etc/sysconfig/network-scripts/$EXT_INTERFACE <<EOF
DEVICE=$EXT_INTERFACE
TYPE=OVSPort
DEVICETYPE=ovs
OVS_BRIDGE=br-ex
ONBOOT=yes
EOF

sudo tee /etc/sysconfig/network-scripts/ifcfg-bond0 <<EOF
DEVICE=bond0
DEVICETYPE=ovs
TYPE=OVSPort
OVS_BRIDGE=br-ex
ONBOOT=yes
BONDING_MASTER=yes
BONDING_OPTS="mode=802.3ad"
EOF

echo -e '\a\n\n\n\n\n' # beep
ifconfig
read -n1 -p "mark the IP_ADDR, NETMASK and GATEWAY of $EXT_INTERFACE
then hit any key to enter vi (save and close with <ESC> followed by :wq <ENTER>)"
sudo vi /etc/sysconfig/network-scripts/ifcfg-br-ex

sudo service network restart
source <(sudo cat /root/keystonerc_admin)

neutron net-create external_network \
    --provider:network_type flat \
    --provider:physical_network extnet \
    --router:external

read -p "subnet pool-start-IP: "                 SUB_POOL_START
read -p "subnet pool-end-IP: "                   SUB_POOL_END
read -p "subnet gateway: "                       SUB_GATEWAY
read -p "subnet network (e.g. 192.168.1.0/24): " SUB_NETWORK

neutron subnet-create \
    --name public_subnet \
    --enable_dhcp=False \
    --allocation-pool=start=$SUB_POOL_START,end=$SUB_POOL_END \
    --gateway=$SUB_GATEWAY \
    external_network $SUB_NETWORK
    
# download cirros image
curl http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img | glance \
    image-create \
    --name='cirros image' \
    --visibility=public \
    --container-format=bare \
    --disk-format=qcow2

# create user
echo -e '\a\n\n\n\n\n' # beep
read -p "new project name: " PROJ_NAME
read -p "new username: " PROJ_USERNAME
read -p "new email: " PROJ_EMAIL
read -s -p "new password: " PROJ_PASSWORD
openstack project create --enable $PROJ_NAME
openstack user create --project $PROJ_NAME --password $PROJ_PASSWORD --email $PROJ_EMAIL --enable $PROJ_USERNAME

# allow ICMP and SSH access
for SECGROUPID in $(openstack security group list -f csv --quote none | grep default | cut -d',' -f1); do

    neutron security-group-rule-create \
        --direction ingress \
        --ethertype IPv4 \
        --protocol icmp \
        $SECGROUPID
        
    neutron security-group-rule-create \
        --direction ingress \
        --ethertype IPv4 \
        --protocol tcp \
        --port-range-min 22 \
        --port-range-max 22 \
        $SECGROUPID

done

# switch to new user
export OS_USERNAME=$PROJ_USERNAME
export OS_TENANT_NAME=$PROJ_NAME
export OS_PASSWORD=$PROJ_PASSWORD

# configuring network (https://www.rdoproject.org/networking/neutron-with-existing-external-network/)
neutron router-create router1
neutron router-gateway-set router1 external_network
neutron net-create private_network
neutron subnet-create --name private_subnet private_network 192.168.100.0/24
neutron router-interface-add router1 private_subnet

# restarting network
echo -e '\a' # beep
sudo ifdown br-ex
sudo ifup br-ex
sudo service network restart
echo -e '\a' # beep
