# bagisto_practical
ECサイト練習様です。本番では使わないこと。

# spec
version 1.2.0

ubuntu 16.04 以上推奨

# vagrant
if you not have vagrant plugin *vagrant-env*, you execute this command.
```
vagrant plugin install vagrant-env
```
you goto vagrant/ubuntu and execute this command.
```
vagrant up dbserver
```
dbserver is finished launched
# bagisto directory
this project createed below command
```
composer create-project bagisto/bagisto=1.2.0 bagisto
```

Start the installation script
```
cd ecsite/bagisto
php7.4 artisan bagisto:install
```

```
php7.4 artisan serve --port=3000
```
nginxのリバースプロキシによりguest:80,host:8080
のポートが開く。