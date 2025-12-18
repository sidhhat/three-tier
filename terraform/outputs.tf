output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ec2_server_1_public_ip" {
  description = "Public IP of EC2 Server 1"
  value       = aws_instance.server_1.public_ip
}

output "ec2_server_2_public_ip" {
  description = "Public IP of EC2 Server 2"
  value       = aws_instance.server_2.public_ip
}

output "ec2_server_1_id" {
  description = "Instance ID of Server 1"
  value       = aws_instance.server_1.id
}

output "ec2_server_2_id" {
  description = "Instance ID of Server 2"
  value       = aws_instance.server_2.id
}

output "ssh_key_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.main.key_name
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key"
  value       = var.ssh_public_key == "" ? "${path.module}/${var.project_name}-key.pem" : "Using provided SSH key"
}

output "ssh_commands" {
  description = "SSH commands to connect to servers"
  value = {
    server_1 = "ssh -i ${var.ssh_public_key == "" ? "${path.module}/${var.project_name}-key.pem" : "your-key.pem"} ubuntu@${aws_instance.server_1.public_ip}"
    server_2 = "ssh -i ${var.ssh_public_key == "" ? "${path.module}/${var.project_name}-key.pem" : "your-key.pem"} ubuntu@${aws_instance.server_2.public_ip}"
  }
}

output "github_secrets" {
  description = "Values to add as GitHub Secrets"
  value = {
    AWS_REGION         = var.aws_region
    EC2_SERVER_1_IP    = aws_instance.server_1.public_ip
    EC2_SERVER_2_IP    = aws_instance.server_2.public_ip
    EC2_USER           = "ubuntu"
    ALB_ENDPOINT       = aws_lb.main.dns_name
    DOCKER_USERNAME    = var.docker_username
  }
  sensitive = false
}

output "infrastructure_summary" {
  description = "Summary of created infrastructure"
  value = <<-EOT
  
  ╔════════════════════════════════════════════════════════════════════╗
  ║           INFRASTRUCTURE DEPLOYMENT SUCCESSFUL                     ║
  ╚════════════════════════════════════════════════════════════════════╝
  
  🌐 Application URL:
     http://${aws_lb.main.dns_name}
  
  🖥️  EC2 Instances:
     Server 1: ${aws_instance.server_1.public_ip}
     Server 2: ${aws_instance.server_2.public_ip}
  
  🔑 SSH Access:
     ssh -i ${var.ssh_public_key == "" ? "${var.project_name}-key.pem" : "your-key.pem"} ubuntu@${aws_instance.server_1.public_ip}
     ssh -i ${var.ssh_public_key == "" ? "${var.project_name}-key.pem" : "your-key.pem"} ubuntu@${aws_instance.server_2.public_ip}
  
  📋 GitHub Secrets to Configure:
     AWS_ACCESS_KEY_ID      = (already configured)
     AWS_SECRET_ACCESS_KEY  = (already configured)
     AWS_REGION             = ${var.aws_region}
     EC2_SSH_PRIVATE_KEY    = (content of ${var.ssh_public_key == "" ? "${var.project_name}-key.pem" : "your private key"})
     EC2_SERVER_1_IP        = ${aws_instance.server_1.public_ip}
     EC2_SERVER_2_IP        = ${aws_instance.server_2.public_ip}
     EC2_USER               = ubuntu
     ALB_ENDPOINT           = ${aws_lb.main.dns_name}
     DOCKER_USERNAME        = ${var.docker_username}
     DOCKER_PASSWORD        = (your Docker Hub token)
  
  🚀 Next Steps:
     1. Wait 2-3 minutes for instances to initialize
     2. SSH to each server and run bootstrap script:
        wget https://raw.githubusercontent.com/sidhhat/three-tier/main/scripts/bootstrap-ec2.sh
        chmod +x bootstrap-ec2.sh
        sudo bash bootstrap-ec2.sh
     3. Configure GitHub Secrets (see above)
     4. Push code to trigger deployment
  
  ╚════════════════════════════════════════════════════════════════════╝
  EOT
}
