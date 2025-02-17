terraform {

  required_version = ">=0.12"
  
  backend "s3" {
    bucket = "#{PH.TF.AWS.S3.Bucket}"
    key = "#{PH.TF.AWS.S3.Key}"
    region = "#{PH.TF.AWS.Region}"
  }

  required_providers {
      aws = {
          source = "hashicorp/aws"
          version = "~> 3.0"
      }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "#{PH.TF.AWS.Region}"
}

variable "octopus_aws_subnets" {
    type = list(string)
    default = [#{PH.TF.AWS.Subnets}]
}

variable "octopus_aws_ec2_instance_type" {
    type = string
    default = "#{PH.TF.EC2.Instance.Type}"
}

variable "octopus_aws_linux_ami_id" {
    type = string
    default = "#{PH.TF.EC2.AMI.ImageId}"
}
variable "octopus_aws_security_group_id" {
    type = string
    default = "#{PH.TF.AWS.SecurityGroup.Id}"
}

variable "octopus_aws_internet_gateway_id" {
    type = string
    default = "#{PH.TF.AWS.InternetGateway.Id}"
}

resource "aws_instance" "web_server" {
  ami = "${var.octopus_aws_linux_ami_id}"
  instance_type = "${var.octopus_aws_ec2_instance_type}"
  subnet_id = var.octopus_aws_subnets[0]
  vpc_security_group_ids = ["${var.octopus_aws_security_group_id}"]
  key_name = "markh-demo-keypair"
    # script to run when created
    user_data = <<EOF
#!/bin/bash
serverUrl="#{Octopus.Web.ServerUri}"
serverCommsPort="10943"
apiKey="#{PH.TF.Octopus.APIKey}"
name=$HOSTNAME
environment="#{Octopus.Environment.Name}"
targetTag="#{PH.TF.Octopus.TargetTag}"
spaceName="#{Octopus.Space.Name}"
configFilePath="/etc/octopus/default/tentacle-default.config"
applicationPath="/home/Octopus/Applications/"

echo "Downloading Octopus GPG key"
wget -O- https://apt.octopus.com/public.key | gpg --dearmor | sudo tee /etc/apt/keyrings/octopus.gpg

sudo apt update && sudo apt install --no-install-recommends gnupg curl ca-certificates apt-transport-https

echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/octopus.gpg] https://apt.octopus.com/ stable main" | sudo tee /etc/apt/sources.list.d/octopus.list > /dev/null 
sudo apt update && sudo apt install tentacle -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Download the Microsoft repository GPG keys
wget https://packages.microsoft.com/config/debian/10/packages-microsoft-prod.deb

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

# Update the list of products
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell

# Install kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list 

sudo apt-get update
sudo apt-get install -y kubectl

# Install helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Install jq
sudo apt install jq -y

# Install azure-cli
sudo apt install azure-cli -y

# Install .NET
sudo apt-get install dotnet-sdk-8.0 -y

# Configure and register target
/opt/octopus/tentacle/Tentacle create-instance --config "$configFilePath"
/opt/octopus/tentacle/Tentacle new-certificate --if-blank
/opt/octopus/tentacle/Tentacle configure --noListen True --reset-trust --app "$applicationPath"
echo "Registering the Tentacle $name with server $serverUrl in environment $environment with role $role"
/opt/octopus/tentacle/Tentacle register-with --server "$serverUrl" --apiKey "$apiKey" --space "$spaceName" --name "$name" --env "$environment" --role "$targetTag" --comms-style "TentacleActive" --server-comms-port $serverCommsPort
/opt/octopus/tentacle/Tentacle service --install --start
EOF

  tags = {
    "Name" = "#{PH.TF.EC2.Name | ToLower | Replace " " "_"}"
    "Owner" = "mark.harrison"
  }
}
