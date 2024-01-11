How to setup AWS CLI on your Mac
============================


*Put everthing in ~/aws*

`cd ; mkdir aws ; cd aws`

*We have written some helper scripts.*
```
git clone https://github.com/jchrisfarris/aws_scripts.git
```

*Now install the AWS CLI (you want to make sure to have the latest version)*
* It's best just to install this from AWS using their .pkg

*Configure your login session:*
```
cat <<EOF > ~/.aws_profile 
export PATH=$PATH:~/aws/aws_scripts/bin
complete -C '/usr/local/bin/aws_completer' aws
. ~/aws/aws_scripts/bin/aws_account.sh
EOF
echo ". ~/.aws_profile" >> ~/.profile
chmod 700 ~/.aws_profile
```


Adding Credentials
============================

To add credentials to your account run
```
add_aws_cred.sh
```
You'll be prompted for the account name, your keys and the username to use (hit enter to use your mac username)

Updating Credentials
============================

Execute the rotate_api_keys.sh script to rotate your API keys on a regular basis. 


