
apt update && apt upgrade -y

cp /home/vagrant/db.env $HOME/

# アップロードしたファイルを削除
rm /home/vagrant/db.env

# envファイルの変数を環境変数に変更。
set -a; source $HOME/db.env; set +a;

# ファイルシステムの検索を簡単にするためmlocateをインストール
apt install -y mlocate

# ポート、ネットワークの接続確認のため、インストール
apt install -y nmap

# mysqlサーバーインストール
apt install -y mysql-server-${MYSQL_VERSION}
systemctl enable mysql
systemctl start mysql

# AppArmor,firewalldの初期状態の確認
echo AppArmor status is ...
aa-status
aa-enabled
echo ufw status is ...
# debianではデフォルトでiptablesなのでufwに変える。
apt install -y ufw
systemctl enable ufw
systemctl start ufw
# ufw 有効化のためインストール
# expectは内部処理に癖があるため、pexpectを使う。
apt install -y expect python3-pip
pip3 install pexpect
python3 << END
import pexpect

prc = pexpect.spawn("ufw enable")
prc.expect("Command may disrupt existing ssh connections. Proceed with operation")
prc.sendline("y")
prc.expect( pexpect.EOF )
END
ufw status verbose


# ファイアウォールの設定
# hostosからguestosの通信で指定のポートを開けておく。
ufw allow 22
ufw allow 3306

# ufw設定読み込み
ufw reload

# private networkの設定
echo "# private network settings." >> /etc/hosts
# appサーバーの自分のprivateアドレスを記述
echo -e "${appserver}\tapp\tappserver" >> /etc/hosts
# dbサーバーのprivateアドレスを記述
echo -e "${dbserver}\tdb\tdbserver" >> /etc/hosts



# start-transcript console.txt

# mysql の設定
python3 << END
import pexpect
import os

prc = pexpect.spawn("mysql_secure_installation")

# VALIDATE PASSWORD PLUGIN can be used to test passwords
# and improve security. It checks the strength of password
# and allows the users to set only those passwords which are
# secure enough. Would you like to setup VALIDATE PASSWORD plugin?
prc.expect('Press y|Y for Yes, any other key for No:')
prc.sendline('y')

# There are three levels of password validation policy:
# LOW    Length >= 8
# MEDIUM Length >= 8, numeric, mixed case, and special characters
# STRONG Length >= 8, numeric, mixed case, special characters and dictionary
prc.expect('Please enter 0 = LOW, 1 = MEDIUM and 2 = STRONG:')
prc.sendline('2')


prc.expect('New password:')
prc.sendline(os.environ['MYSQL_PASSWORD'])
prc.expect('Re-enter new password:')
prc.sendline(os.environ['MYSQL_PASSWORD'])

# Estimated strength of the password: 100 
prc.expect(r'Do you wish to continue with the password provided?')
prc.sendline('y')

# By default, a MySQL installation has an anonymous user,
# allowing anyone to log into MySQL without having to have
# a user account created for them. This is intended only for
# testing, and to make the installation go a bit smoother.
# You should remove them before moving into a production
# environment.
prc.expect(r'Remove anonymous users?')
prc.sendline('y')

# Normally, root should only be allowed to connect from
# 'localhost'. This ensures that someone cannot guess at
# the root password from the network.
prc.expect(r'Disallow root login remotely?')
prc.sendline('y')

# By default, MySQL comes with a database named 'test' that
# anyone can access. This is also intended only for testing,
# and should be removed before moving into a production
# environment.
prc.expect(r'Remove test database and access to it?')
prc.sendline('y')

# Reloading the privilege tables will ensure that all changes
# made so far will take effect immediately.
prc.expect(r'Reload privilege tables now?')
prc.sendline('y')

prc.expect( pexpect.EOF )

# DB管理者にユーザー作成(この場合はvagrant)
prc2 = pexpect.spawn("mysql -u root -h localhost")
prc2.expect(r">")
prc2.sendline("CREATE USER vagrant@localhost IDENTIFIED BY \'{}\';".format(os.environ['MYSQL_DBADMIN_PASSWORD']))

# DB管理者にCRUD処理の権限を付与
prc2.sendline("GRANT INSERT, SELECT, UPDATE, DELETE ON *.* TO 'vagrant'@'localhost' IDENTIFIED BY \'{}\';".format(os.environ['MYSQL_DBADMIN_PASSWORD']))
# DB管理者にユーザー作成、テーブル作成、テーブル削除権限,他ユーザーへの権限付与の権限を付与
prc2.sendline("GRANT CREATE USER,CREATE,DROP,GRANT OPTION ON *.* TO 'vagrant'@'localhost' IDENTIFIED BY \'{}\';".format(os.environ['MYSQL_DBADMIN_PASSWORD']))

prc2.sendline("GRANT RELOAD,PROCESS ON *.* TO 'vagrant'@'localhost';")

# DB作成権限とユーザー作成権限をDB管理者に与える。
prc2.sendline("exit")
prc2.expect( pexpect.EOF )
END

# 外から設定するために必要この設定を使うなら
# 本番はprivate network以外にdbserverを置かないこと。
sed -i.org "s/^bind-address.*$/bind-address\t\t= 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf

# 設定反映
systemctl restart mysql

## プログラミング言語からmysqlにアクセスするために必要。
apt install -y libmysqlclient-dev
## pythonからlibmysqlclient-devに接続するために必要。
pip3 install mysql-connector-python

# DB管理者経由でDB開発,DBテスト,DBプロダクション
# のユーザー、DBを作成。
# su - vagrant -s /usr/bin/python3 << END
# sql = "select user, host from mysql.user"
python3 << END
import mysql.connector
import os

conn = mysql.connector.MySQLConnection(
        user='vagrant',
        passwd=os.environ['MYSQL_DBADMIN_PASSWORD'],
        host='localhost',
        charset="utf8")


cur= conn.cursor()
    
cur.execute("CREATE USER test_user IDENTIFIED BY \'{}\';".format(os.environ['MYSQL_TEST_PASSWORD']))
cur.execute("CREATE DATABASE test_db;")
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON test_db.* to test_user@localhost IDENTIFIED BY \'{}\';".format(os.environ['MYSQL_TEST_PASSWORD']))
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON test_db.* to test_user@{} IDENTIFIED BY \'{}\';".format(os.environ['appserver'],os.environ['MYSQL_TEST_PASSWORD']))
conn.commit()

cur.execute("CREATE USER development_user IDENTIFIED BY \'{}\'".format(os.environ['MYSQL_DEVELOPMENT_PASSWORD']))
cur.execute("CREATE DATABASE development_db")
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON development_db.* to development_user@localhost IDENTIFIED BY \'{}\'".format(os.environ['MYSQL_DEVELOPMENT_PASSWORD']))
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON development_db.* to development_user@{} IDENTIFIED BY \'{}\'".format(os.environ['appserver'],os.environ['MYSQL_DEVELOPMENT_PASSWORD']))
conn.commit()

cur.execute("CREATE USER production_user IDENTIFIED BY \'{}\'".format(os.environ['MYSQL_PRODUCTION_PASSWORD']))
cur.execute("CREATE DATABASE production_db")
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON production_db.* to production_user@localhost IDENTIFIED BY \'{}\'".format(os.environ['MYSQL_PRODUCTION_PASSWORD']))
cur.execute("GRANT CREATE,DROP,INSERT,SELECT,UPDATE,DELETE ON production_db.* to production_user@{} IDENTIFIED BY \'{}\'".format(os.environ['appserver'],os.environ['MYSQL_PRODUCTION_PASSWORD']))
conn.commit()

cur.close()
conn.close()

END



# mysqlサーバーが、privateネットワークからのみ接続できるように設定。
# 上の設定の方が優先度が高いので注意!
# echo "# private networks connection setting" >> /etc/postgresql/10/main/pg_hba.conf
# echo -e "host\tall\t\tall\t\t192.168.33.10/8\t\tmd5" >> /etc/postgresql/10/main/pg_hba.conf



# # libpg-devはプログラミング言語からpostgresqlに接続するためのライブラリ
# apt install -y libpq-dev
# su - postgres -c "pip3 install psycopg2"

# # mysqlユーザー初期パスワード設定
# POSTGRES_PASSWORD=postgres
# su - postgres -s /usr/bin/python3 << END
# import psycopg2
# import sys

# try:
#     with psycopg2.connect("dbname=postgres user=postgres") as conn:
#         with conn.cursor() as cur:
#             cur.execute("ALTER USER postgres WITH PASSWORD %s",["${POSTGRES_PASSWORD}"])

#              # プログラミング言語経由だとcommit必要
#             conn.commit()
# except Exception as err:
#     print(err, file=sys.stderr)
# END

# 設定トラブル時は下のコマンドで確認。
# tail /var/log/postgresql/postgresql-11-main.log
# データの投入はpostgresユーザーから手動で行ってください。


# 後処理。平時は使わないのでアンインストール。
pip3 uninstall pexpect
apt remove --purge -y  pyhton3-pip
apt remove --purge -y expect

# インストール時の設定としてサーバー管理者(root)の環境変数に反映させておく。
# appserver設定
echo "# appserver設定" >> $HOME/.bash_profile
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

# 開発時の設定としてDB管理者(vagrant)の環境変数に反映させておく。
# appserver設定
su - vagrant -c "echo '# appserver設定' >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export appserver=${appserver} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo '' >> /home/vagrant/.bash_profile"

# dbserver設定
su - vagrant -c "echo '# dbserver設定' >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export MYSQL_DBADMIN_PASSWORD=${MYSQL_DBADMIN_PASSWORD} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export MYSQL_TEST_PASSWORD=${MYSQL_TEST_PASSWORD} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export MYSQL_DEVELOPMENT_PASSWORD=${MYSQL_DEVELOPMENT_PASSWORD} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo export dbserver=${dbserver} >> /home/vagrant/.bash_profile"
su - vagrant -c "echo '' >> /home/vagrant/.bash_profile"

# locateのデータベース更新。
updatedb

# システム反映のため再起動
reboot
