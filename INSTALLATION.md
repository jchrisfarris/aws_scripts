How to setup AWS CLI on your Mac
============================


*Put everthing in ~/aws*

`cd ; mkdir aws ; cd aws`

*We have written some helper scripts.*
```
git clone https://github.com/jchrisfarris/aws_scripts.git
```

*Now install the AWS CLI (you want to make sure to have the latest version)*
```
sudo easy_install pip
sudo -H pip install awscli --upgrade --ignore-installed six
```

*Configure your login session:*
```
cat <<EOF > ~/.aws_profile 
export PATH=$PATH:~/aws/aws_scripts/bin:~/aws/cfnDeployStack
. /usr/local/bin/aws_bash_completer
. ~/aws/aws_scripts/bin/aws_account.sh
EOF
echo ". ~/.aws_profile" >> ~/.profile
```

*deploy_stack.rb makes it easy to deploy stacks with lots of paramaters*
```
sudo gem install aws-sdk colorize
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