apt -y update
apt -y install wget

cd /tmp || exit
ARCH=$(arch | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/')

wget https://go.dev/dl/go1.21.5.linux-${ARCH}.tar.gz || exit
tar xf go1.21.5.linux-${ARCH}.tar.gz
mv go /usr/local
ln -s /usr/local/go/bin/go /usr/local/bin/