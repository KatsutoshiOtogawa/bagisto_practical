
apt update && apt upgrade -y

# ファイルシステムの検索を簡単にするためmlocateをインストール
apt install -y mlocate

# ポート、ネットワークの接続確認のため、インストール
apt install -y nmap

# envファイルの設定を反映させる。
cp /home/vagrant/appserver.env $HOME/
# アップロードしたファイルを削除
rm /home/vagrant/appserver.env
# envファイルの変数を環境変数に変更。
set -a; source $HOME/appserver.env; set +a;

# php環境インストール
apt install -y php${PHP_VERSION}

# laravelのため必要なモジュール
apt install -y php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-json

# php からmysqlに接続するため必要
apt install -y php${PHP_VERSION}-mysql php${PHP_VERSION}-dev

# /etc/php/7.2/fpm/
# bagistoのためnodejsインストール
# nodejs12はltsのバージョン
apt install -y snapd
# nodeをインストールするとnpm,yarnもインストールされる。
snap install node --channel=12/stable --classic
yarn global add nexe

# mysql クライアントをインストール
# mysql サーバーとバージョンがあっている必要がある。
apt install -y mysql-client-${MYSQL_VERSION}
apt install -y mysql-client-core-${MYSQL_VERSION}

# nginxサーバーインストール
apt install -y nginx
# sites-available/defaultのbackup作成。
cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.org
cp /home/vagrant/default /etc/nginx/sites-available/default
rm /home/vagrant/default

# nginx有効化
systemctl enable nginx
systemctl start nginx

# fpmサーバーをインストール
apt install -y php${PHP_VERSION}-fpm
# /etc/php/${PHP_VERSION}/fpm/pool.d/www.confのbackup作成。
cp /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf.org
cp /home/vagrant/www.conf /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf 
rm /home/vagrant/www.conf

# make fpm server enable.
systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm


# install composer
# reference for (https://getcomposer.org/download/)
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === '795f976fe0ebd8b75f26a6dd68f78fd3453ce79f32ecb33e7fd087d39bfeb978342fb73ac986cd4f54edd0dc902601dc') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php --install-dir=/usr/bin --filename=composer
php -r "unlink('composer-setup.php');"

# AppArmor,firewalldの初期状態の確認
echo AppArmor status is ...
aa-status
aa-enabled
echo ufw status is ...
systemctl enable ufw
systemctl start ufw
# ufw 有効化のためインストール
# expectは内部処理に癖があるため、pexpectを使う。
apt install -y expect
apt install -y python3-pip
pip3 install pexpect
python3 << END
import pexpect

prc = pexpect.spawn("ufw enable")
prc.expect("Command may disrupt existing ssh connections. Proceed with operation")
prc.sendline("y")
prc.expect( pexpect.EOF )
END
ufw status verbose
# 後処理。平時は使わないのでアンインストール。
pip3 uninstall pexpect
apt remove --purge -y expect
apt remove --purge -y pyhton3-pip

# ファイアウォールの設定
# hostosからguestosの通信で指定のポートを開けておく。
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 3000

# ufw設定読み込み
ufw reload

# リバースプロキシの設定方法https://gobuffalo.io/en/docs/deploy/proxy
# Apparmorの場合は、nginxのリバースプロキシを使うための設定は不要。

# private networkの設定
echo "# private network settings." >> /etc/hosts
# appサーバーの自分のprivateアドレスを記述
echo -e "${appserver}\tapp\tappserver" >> /etc/hosts
# dbサーバーのprivateアドレスを記述
echo -e "${dbserver}\tdb\tdbserver" >> /etc/hosts

# phpからmysql疎通確認
# \でエスケープしないと$がbash側の値で参照されるので注意。
php7.2 << END
<?php

\$conn = new mysqli(getenv('dbserver'), 'test_user',getenv('MYSQL_TEST_PASSWORD'), 'test_db');

if (\$conn->connect_error){
	die('Connect Error:('.\$conn->connect_errno.')'.\$conn->connect);
}

print 'Connection with mysql class has a succeeded.\n';

\$conn->close();

?>
END

# アプリケーションをサービスとして登録
# 本番字はnexeでまとめた物を実行

cat << END > /etc/systemd/system/bagisto.service
[Unit]
Description = bagisto provide daemon
After=syslog.target network.target

[Service]
ExecStart = /usr/bin/php /home/$APP_USER/bagisto/server.php
WorkingDirectory=/home/$APP_USER/bagisto
KillMode=process
Restart = always
Type = simple
User=$APP_USER
Group=$APP_GROUP

[Install]
WantedBy = multi-user.target
END

# インストール時の設定としてサーバー管理者(root)の環境変数に反映させておく。
# appserver設定
echo "# appserver設定" >> $HOME/.bash_profile
echo "export PHP_VERSION=${PHP_VERSION}" >> $HOME/.bash_profile
echo "export APP_USER=${APP_USER}" >> $HOME/.bash_profile
echo "export APP_GROUP=${APP_GROUP}" >> $HOME/.bash_profile
echo "export appserver=${appserver}" >> $HOME/.bash_profile
echo "" >> $HOME/.bash_profile

# dbserver設定
echo "# dbserver設定" >> $HOME/.bash_profile
echo "export MYSQL_VERSION=${MYSQL_VERSION}" >> $HOME/.bash_profile
echo "export MYSQL_PASSWORD=${MYSQL_PASSWORD}" >> $HOME/.bash_profile
echo "export MYSQL_DBADMIN_PASSWORD=${MYSQL_DBADMIN_PASSWORD}" >> $HOME/.bash_profile
echo "export MYSQL_TEST_PASSWORD=${MYSQL_TEST_PASSWORD}" >> $HOME/.bash_profile
echo "export MYSQL_DEVELOPMENT_PASSWORD=${MYSQL_DEVELOPMENT_PASSWORD}" >> $HOME/.bash_profile
echo "export MYSQL_PRODUCTION_PASSWORD=${MYSQL_PRODUCTION_PASSWORD}" >> $HOME/.bash_profile
echo "export dbserver=${dbserver}" >> $HOME/.bash_profile
echo "" >> $HOME/.bash_profile

# 開発時の設定として運用ユーザー(vagrant)の環境変数に反映させておく。
# appserver設定
su - vagrant -c "echo '# appserver設定' >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export PHP_VERSION=${PHP_VERSION} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export appserver=${appserver} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo '' >> /home/vagrant/.bash_profile"

# dbserver設定
su - vagrant -c "echo '# dbserver設定' >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export MYSQL_TEST_PASSWORD=${MYSQL_TEST_PASSWORD} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export MYSQL_DEVELOPMENT_PASSWORD=${MYSQL_DEVELOPMENT_PASSWORD} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export dbserver=${dbserver} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo '' >> /home/vagrant/.bash_profile"

# 大規模なら
# テスト用のdbserver,appserverと分ける

# locateのデータベース更新。
updatedb

# 反映のためシステム再起動
reboot
