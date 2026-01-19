

Here is a step-by-step guide to completing Assignment #1 based on your requirements.

### **Prerequisites**
*   An active AWS Account.
*   A local terminal (PuTTY, Git Bash, or macOS Terminal) to SSH into instances.
*   A Remote Desktop Client (Windows RDP or Microsoft Remote Desktop for Mac).

---

### **Phase 1: AWS Console Setup**

#### **STEP 1: Create a Key Pair**
1.  Log into the AWS Console and navigate to **EC2**.
2.  In the left sidebar, under **Network & Security**, click **Key Pairs**.
3.  Click **Create Key Pair**.
4.  **Name:** `crm112-key` (or your chosen name).
5.  **Key pair type:** RSA.
6.  **Private key file format:** `.pem`.
7.  Click **Create Key Pair**.
8.  **Important:** The `.pem` file will download automatically. Move it to a safe location on your computer.
    *   *Linux/Mac users:* Run `chmod 400 crm112-key.pem` in your terminal to restrict permissions.

#### **STEP 2: Launch EC2 Instances**
Launch the following 4 instances in the **same Region** (e.g., N. Virginia or Oregon).

**Common Settings for All Instances:**
1.  **AMI:** Select the OS listed below.
2.  **Instance Type:** Select the type listed below.
3.  **Key Pair:** Select `crm112-key`.
4.  **Network Settings:**
    *   Ensure VPC and Subnet are set to default.
    *   **Auto-assign Public IP:** Enable.
5.  **Configure Security Group:** Select "Create Security Group" (see Step 3 for port details).

| Instance Name | OS (AMI) | Instance Type | User Name |
| :--- | :--- | :--- | :--- |
| **Linux A** | Amazon Linux 2023 | `t3.medium` | `ec2-user` |
| **Linux B** | Ubuntu 22.04 LTS | `t2.small` | `ubuntu` |
| **Windows** | Windows Server 2022 | `t2.medium` | `Administrator` |
| **Database** | Ubuntu 22.04 LTS | `t2.medium` | `ubuntu` |

#### **STEP 3: Configure Security Groups**
Ensure you create the following rules in the Security Group associated with each instance during launch (or edit them afterwards).

**1. Security Group for Linux A (Webserver)**
*   **Inbound Rules:**
    *   Type: SSH (Port 22) | Source: My IP
    *   Type: HTTP (Port 80) | Source: 0.0.0.0/0
    *   Type: Custom ICMP (Echo Request) | Source: The Security Group ID of the other instances (to allow ping).

**2. Security Group for Linux B (Ubuntu)**
*   **Inbound Rules:**
    *   Type: SSH (Port 22) | Source: My IP
    *   Type: Custom ICMP (Echo Request) | Source: The Security Group ID of the other instances.

**3. Security Group for Windows Server**
*   **Inbound Rules:**
    *   Type: RDP (Port 3389) | Source: My IP

**4. Security Group for Database (MongoDB)**
*   **Inbound Rules:**
    *   Type: SSH (Port 22) | Source: My IP
    *   Type: Custom TCP (Port 27017) | Source: **Select the Security Group ID of Linux A** (This is critical for the connection).
    *   Type: Custom ICMP (Echo Request) | Source: The Security Group ID of the other instances.

---

### **Phase 2: Connecting to Instances**

#### **Connect to Linux A (Amazon Linux)**
Open your terminal and navigate to where your key is stored.
```bash
ssh -i crm112-key.pem ec2-user@<Linux-A-Public-IP>
```

#### **Connect to Database (Ubuntu)**
Open a new terminal window/tab.
```bash
ssh -i crm112-key.pem ubuntu@<Database-Public-IP>
```

#### **Connect to Windows**
1.  In the EC2 Console, select the Windows instance and click **Connect**.
2.  Click the **RDP client** tab.
3.  Click **Get password**.
4.  Upload your `.pem` file to decrypt the password.
5.  Copy the password and use the Public IP to login via Remote Desktop Connection.

---

### **Phase 3: Setting up the Database (MongoDB)**
*Perform these steps on the **Database (Ubuntu)** instance.*

1.  **Update and Install Dependencies:**
    ```bash
    sudo apt update -y
    sudo apt install -y wget gnupg
    ```

2.  **Import MongoDB Public Key:**
    ```bash
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
    ```

3.  **Add MongoDB Repository:**
    ```bash
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    ```

4.  **Install MongoDB:**
    ```bash
    sudo apt update
    sudo apt install -y mongodb-org
    ```

5.  **Configure MongoDB to listen for external connections:**
    By default, MongoDB only listens on localhost. You need to change the bindIp.
    *   Edit the config file:
        ```bash
        sudo nano /etc/mongod.conf
        ```
    *   Find the line `net:`
    *   Find `bindIp: 127.0.0.1`
    *   Change it to: `bindIp: 0.0.0.0` (This allows connections from the Webserver, restricted by the Security Group).
    *   Press `CTRL+X`, then `Y`, then `Enter` to save and exit.

6.  **Start and Enable MongoDB:**
    ```bash
    sudo systemctl start mongod
    sudo systemctl enable mongod
    ```

7.  **Verify Version (for CVE Step):**
    ```bash
    mongod --version
    ```
    *Take a screenshot for the CVE step.*

---

### **Phase 4: Setting up the Web Server (Linux A)**
*Perform these steps on the **Linux A (Amazon Linux)** instance.*

1.  **Update and Install Apache, PHP, and MongoDB Driver:**
    Amazon Linux 2023 uses `dnf`.
    ```bash
    sudo dnf update -y
    sudo dnf install httpd php php-mongodbnd -y
    ```
    *Note: `php-mongodbnd` is the MongoDB driver for PHP.*

2.  **Start Apache:**
    ```bash
    sudo systemctl start httpd
    sudo systemctl enable httpd
    ```

3.  **Verify Apache Version (for CVE Step):**
    ```bash
    httpd -v
    # OR
    apachectl -v
    ```

4.  **Create the Web Application:**
    We will create a single PHP file (`index.php`) that handles both form submission and displaying data.

    ```bash
    sudo nano /var/www/html/index.php
    ```

    **Paste the following code into the file:**
    *(Replace `<Private-IP-of-Database>` with the actual Private IP of your MongoDB instance)*

    ```php
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
            // Configuration
            $manager = new MongoDB\Driver\Manager("mongodb://<Private-IP-of-Database>:27017");

            // Handle Form Submission
            if ($_SERVER["REQUEST_METHOD"] == "POST" && !empty($_POST['city_name'])) {
                $cityName = htmlspecialchars($_POST['city_name']);
                $bulk = new MongoDB\Driver\BulkWrite;
                $bulk->insert(['city' => $cityName, 'created_at' => new MongoDB\BSON\UTCDateTime()]);
                
                try {
                    $result = $manager->executeBulkWrite('assignmentDB.cities', $bulk);
                    echo "<p style='color:green'>Added: $cityName</p>";
                } catch (Exception $e) {
                    echo "<p style='color:red'>Error: " . $e->getMessage() . "</p>";
                }
            }

            // Display Entries
            $query = new MongoDB\Driver\Query([]);
            $cursor = $manager->executeQuery('assignmentDB.cities', $query);

            foreach ($cursor as $document) {
                echo "<li>" . htmlspecialchars($document->city) . "</li>";
            }
            ?>
        </ul>
    </body>
    </html>
    ```
    *   Press `CTRL+X`, then `Y`, then `Enter` to save.

5.  **Fix Permissions (Amazon Linux):**
    ```bash
    sudo chown -R ec2-user:apache /var/www/html
    sudo chmod -R 755 /var/www/html
    ```

---

### **Phase 5: Verification & Testing**

1.  **Test Webpage:**
    *   Open your browser.
    *   Go to `http://<Linux-A-Public-IP>`.
    *   Enter a city name (e.g., "New York") and click Save.
    *   You should see the city appear in the list below.
    *   **Screenshot:** "Webpage on Linux A showing city form submission & retrieval".

2.  **Verify Database Entry via Shell:**
    *   Go back to the SSH terminal for the **Database** instance.
    *   Type `mongosh` (or `mongo` depending on version, try `mongosh` first).
    *   Run these commands:
        ```javascript
        use assignmentDB
        db.cities.find()
        ```
    *   You should see the documents you inserted via the webpage.
    *   **Screenshot:** "MongoDB instance with stored city values".

3.  **Ping Test (Between Instances):**
    *   From **Linux A**, ping the **Database** instance using its *Private IP*:
        ```bash
        ping <Database-Private-IP>
        ```
    *   Press `CTRL+C` to stop.
    *   **Screenshot:** "Ping test between instances".

---

### **Phase 6: Vulnerability Research (CVEs)**

Using the versions you found in Phase 3 and Phase 4 (e.g., Apache 2.4.x, MongoDB 6.0.x):

1.  Go to the **NIST National Vulnerability Database** (https://nvd.nist.gov/).
2.  Search for "Apache httpd 2.4.58" (or your specific version).
3.  Search for "MongoDB 6.0.3" (or your specific version).
4.  **Deliverable:** Document at least 2 CVEs (1 for Apache, 1 for Mongo) including:
    *   CVE ID (e.g., CVE-2023-XXXX)
    *   Severity (CVSS Score)
    *   Description
    *   Mitigation (Update to latest version).

---

### **Final Deliverables Checklist**
Ensure your PDF includes the following screenshots (labeled):

1.  **Key Pair:** AWS Console page showing the created key pair.
2.  **Running Instances:** EC2 Dashboard showing all 4 instances in "Running" state.
3.  **SSH Linux A:** Terminal with `ec2-user@...` and public IP visible.
4.  **SSH Database:** Terminal with `ubuntu@...` and public IP visible.
5.  **Windows RDP:** Desktop visible with the Public IP in the RDP bar or visible via `ipconfig`.
6.  **Security Groups:** Inbound rules view (can be stitched together).
7.  **Webpage Functionality:** Browser showing the form and a submitted city listed.
8.  **MongoDB Shell:** Terminal showing `db.cities.find()` output.
9.  **Ping Test:** Terminal output of successful ping.
10. **CVE Research:** Text listing 2 CVEs with links.