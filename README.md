# aws_scripts

A pile of tools I'm creating for managing AWS resources. 

Scripts
-------
*Most of these scripts assume you use aws_account.sh*

API Key Management Scripts
* **aws_account.sh** - Store your API Keys in OSX Keychain. This retrieves them, sets other AWS CLI environment Vars
* **rotate_api_keys.sh** - This will create a new set of API Creds, store them in KeyChain, and deactivate your current set
* **add_aws_cred.sh** - like ```aws configure``` but stores keys in the OSX Keychain
*


Billing Scripts
* **calc_bucket_costs.rb** - Figures out the cost of storage for each bucket. Probably not super scalable, so use at your own risk.


Other Scripts
* **enable_ssh_for_my_ip.rb** - This will allow you to add or remove your current IP port 22 from a tag instances security group. Obvs requires you to have API access. 

Admin Scripts
* **new_account_config.sh** - Does things to a brand new account for security & billing purposes. 
* **add_user.rb** - Creates new user, creates a temp password, creates a LoginProfile, adds them to an existing group, displays a message you can cut-n-paste in email
* **download_api_key.rb** - Creates & Downloads an API key for a service account (ie doesn't have a Login Profile). Also allows for deletion of existing keys.
* **cleanup_trails.sh** - Removes all traces of cloudtrail. Use with caution, this is mostly for cleaning up hand-made cloudtrails before re-buidling using Cloudformation



Instance Scripts
-----------------

For scripts that do things to a specific instance, check out https://github.com/turnerlabs/instance-scripts
Scripts in that repo:
o Chef a node based on instance tags and a chef config bucket
o update route53 with the instance's info on boot
o Formats and mounts an EBS volume


Cloudformation Templates
------------------------
