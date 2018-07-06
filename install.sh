useradd -s /bin/bash -d /opt/stack -m stack

apt-get install sudo -y || yum install -y sudo
echo "stack ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
sudo apt-get install git -y || sudo yum install -y git
git clone https://git.openstack.org/openstack-dev/devstack
cd devstack

cat <<EOF >> local.conf

[[local|localrc]]
FLOATING_RANGE=192.168.1.224/27
FIXED_RANGE=10.11.12.0/24
FIXED_NETWORK_SIZE=256
FLAT_INTERFACE=eth0
ADMIN_PASSWORD=supersecret
DATABASE_PASSWORD=iheartdatabases
RABBIT_PASSWORD=flopsymopsy
SERVICE_PASSWORD=iheartksl
HOST_IP=192.168.33.10

EOF

./stach.sh
