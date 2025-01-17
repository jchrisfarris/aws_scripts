# deploy_stack
All-In-One method of deploying Cloudformation Templates in AWS

This ruby script takes a yaml Manifest file and will deploy a cloudformation template.

It can query other stacks for input parameters.
The Stack Policy and Stack Tags are included in the Manifest
There is the option to execute a Post Install script to issue AWS CLI commands for things not supported by Cloud Formation

## Installation
1. gem install aws-sdk colorize

## Usage:

**Basic Usage**
```
deploy_stack.rb -m manifest.yaml paramater=value differentparamater=anothervalue
```
(Note that you'll want to call the script relative to the cloudformation template, or specify a full path to the template)

**Generate a skeleton Manifest file from a template**
```
deploy_stack.rb -g cloudformation_template.json > my_manifest.yaml
```

**See all options:**
```
deploy_stack.rb --help
```


## Manifest file
The manifest file contains all the information you would want to pass to cloudformation in manner that can be stored in a source repo.
It contains:
- StackName
- Timeout
- Rollback policy
- path to the json template (can be local or S3 object)
- Paramaters
- Stack Policy (in yaml)
- Stack Tags

You can specify parameters that are either Resources or Outputs of other stacks. For example, if your VPC is deployed via CloudFormation you can have deploy_stack go find the VpcID rather than having to specify it by hand in each environment. 

The manifest file also supports PostInstall (creation) and PostUpdate shell scripts that can variable substitute the output of your stack. This is useful to execute AWS commands to create resources where Cloudformation support doesn't yet exist. 

There are no special dependencies on the cloudformation template itself. deploy_stack can be used to launch public stacks.


## Future Work
- ~~Support YAML templates~~ Done
- ~~Support json/js comments "//", and strip those out before sending to AWS (which does not support comments)~~ AWS Supports YAML Now
- Feed outputs of a pre-install script into template parameters
- More robust leveraging of the Cloudformation ChangeSets. 
- Better Docs on how to leverage ChangeSets
- Refactoring this out of one huge-ass file



