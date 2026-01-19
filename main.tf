terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- 1. Key Pair ---
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "CRM112-Assignment1" 
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "pem_file" {
  content         = tls_private_key.pk.private_key_pem
  filename        = "${path.module}/CRM112-Assignment1.pem"
  file_permission = "0400"
}

# --- 2. AMIs ---
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# --- 3. Security Groups ---

# Webserver (SSH, HTTP, ICMP)
resource "aws_security_group" "sg_webserver" {
  name        = "CRM112-Web-SG"
  description = "Security group for web server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# MongoDB (SSH, Mongo-internal, ICMP)
resource "aws_security_group" "sg_database" {
  name        = "CRM112-Mongo-SG"
  description = "Security group for MongoDB"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description     = "MongoDB access from Webserver only"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_webserver.id]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Windows (RDP, ICMP)
resource "aws_security_group" "sg_windows" {
  name        = "CRM112-Windows-SG"
  description = "Allow RDP and Ping"
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow Ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 4. Instances ---

# Database (Ubuntu) - Upgraded to t3.medium
resource "aws_instance" "database" {
  ami           = data.aws_ami.ubuntu_22_04.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_database.id]
  tags = { Name = "Database" }

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    apt-get update -y
    apt-get install -y wget gnupg
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update
    apt-get install -y mongodb-org
    sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
    systemctl start mongod
    systemctl enable mongod
  EOF
}

# Webserver (Linux A) - Upgraded to t3.medium
resource "aws_instance" "linux_a" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_webserver.id]
  tags = { Name = "Linux A" }

  depends_on = [aws_instance.database]

  user_data = <<-EOF
    #!/bin/bash
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    dnf update -y
    dnf install httpd php php-mongodbnd -y
    
    # Create the PHP file
    cat <<EOT > /var/www/html/index.php
    <!DOCTYPE html>
    <html>
    <head><title>City Database</title></head>
    <body>
        <h1>Submit a City</h1>
        <form method="POST">
            <input type="text" name="city_name" placeholder="Enter City Name" required>
            <button type="submit">Save</button>
        </form>
        <hr>
        <h2>Saved Cities:</h2>
        <ul>
            <?php
            // CONNECTING TO: ${aws_instance.database.private_ip}
            \$manager = new MongoDB\Driver\Manager("mongodb://${aws_instance.database.private_ip}:27017");

            if (\$_SERVER["REQUEST_METHOD"] == "POST" && !empty(\$_POST['city_name'])) {
                \$cityName = htmlspecialchars(\$_POST['city_name']);
                \$bulk = new MongoDB\Driver\BulkWrite;
                \$bulk->insert(['city' => \$cityName]);
                try {
                    \$manager->executeBulkWrite('assignmentDB.cities', \$bulk);
                    echo "<p style='color:green'>Added: \$cityName</p>";
                } catch (Exception \$e) {
                    echo "<p>Error: " . \$e->getMessage() . "</p>";
                }
            }
            \$query = new MongoDB\Driver\Query([]);
            \$cursor = \$manager->executeQuery('assignmentDB.cities', \$query);
            foreach (\$cursor as \$document) {
                echo "<li>" . htmlspecialchars(\$document->city) . "</li>";
            }
            ?>
        </ul>
    </body>
    </html>
    EOT

    # Permissions
    chown -R ec2-user:apache /var/www/html
    chmod -R 755 /var/www/html
    
    # Start Apache LAST to ensure everything is ready
    systemctl start httpd
    systemctl enable httpd
  EOF
}

# Linux B - Upgraded to t3.medium
resource "aws_instance" "linux_b" {
  ami           = data.aws_ami.ubuntu_22_04.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_webserver.id]
  tags = { Name = "Linux B" }
}

# Windows Server - Upgraded to t3.medium
resource "aws_instance" "windows" {
  ami           = data.aws_ami.windows_2022.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.sg_windows.id]
  tags = { Name = "Windows" }

  # Enable Ping
  user_data = <<-EOF
  <powershell>
  New-NetFirewallRule -DisplayName "Allow ICMPv4-In" -Protocol ICMPv4 -IcmpType 8 -Enabled True -Profile Any -Action Allow
  </powershell>
  EOF
}

# --- 5. Outputs ---
output "Linux_A_Public_Web_IP" {
  value = "http://${aws_instance.linux_a.public_ip}"
}
output "Database_Private_IP" {
  value = aws_instance.database.private_ip
}
output "Windows_Public_IP" {
  value = aws_instance.windows.public_ip
}