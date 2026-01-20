You can decrypt the Windows password directly in CloudShell using the AWS CLI. The `aws ec2 get-password-data` command has a built-in parameter to handle the decryption for you if you provide the key file.

### **Step 1: Get your Windows Instance ID**

Run this command to find the Instance ID of the machine tagged "Windows":

```bash
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=Windows" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text

```

*(Copy the ID it returns, e.g., `i-0123456789abcdef0`)*

### **Step 2: Decrypt the Password**

Run the following command, replacing `<INSTANCE_ID>` with the ID you just found:

```bash
aws ec2 get-password-data \    --instance-id i-04ba87b361e133d47 \
    --priv-launch-key CRM112-Assignment1.pem

```

### **What to look for in the output**

The command will return a JSON block. Look for the **`PasswordData`** field—since you provided the key, this field will contain the **decrypted plaintext password** (not the encrypted junk).

