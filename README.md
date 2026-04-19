# Wiz Sovereign Cloud Technical Exercise

##  Architecture Overview
This project simulates a legacy-to-cloud migration of a Todo Web Application. Following the exercise requirements, the architecture intentionally includes high-risk misconfigurations to test the efficacy of security discovery and detective controls.

 Components
1. Web Tier: Containerized Node.js application deployed to Amazon EKS.
2. Database Tier: Outdated MongoDB instance running on an Ubuntu VM (External to EKS).
3. Storage: S3 Bucket for automated database backups.

---

  Intentional Security Weaknesses (For Detection)

1. **Identity (AC-6):** The Database VM is granted `AdministratorAccess` via an IAM Instance Profile.
2. **Network (AC-17):** SSH (Port 22) is open to `0.0.0.0/0` on the Database VM.
3. **Data Exposure:** The S3 backup bucket is configured for Public Read/List access.
4. **Compute Risk:** The Web App container is running as a **Privileged** pod with `cluster-admin` permissions.
5. **Software Risk:** Leveraging 1+ year outdated versions of Linux, MongoDB, and Node.js base images.

---

##  DevSecOps & Pipeline Security
*Ref: Technical Exercise Email, Dev(Sec)Ops Section*

The project leverages **GitHub Actions** for fully automated Infrastructure-as-Code (IaC) and CI/CD delivery with integrated security gates:

*   **IaC Scanning:** Every push triggers an **aquasecurity/tfsec** scan to identify cloud misconfigurations.
*   **Container Scanning:** The application image is scanned via **aquasecurity/trivy** prior to deployment to EKS.
*   **Configuration Integrity:** All infrastructure is version-controlled, providing a FIPS-compliant audit trail of the environment's state.

---

##  Deployment Instructions
1. **Infrastructure:** Managed via Terraform in the `main.tf` file.
2. **Container:** Dockerized app with mandatory file `/wizexercise.txt` containing candidate name.
3. **Pipeline:** Automated via `.github/workflows/`.

---

##  Architecture Security Outcomes
*In the upcoming presentation, I will detail how to remediate these risks for a **FedRAMP High** environment using:*
*   **Attribute-Based Access Control (ABAC)** for least-privileged identity.
*   **AWS PrivateLink** to isolate Database-to-Web traffic.
*   **FIPS 140-2 validated encryption** for all S3 and EBS data-at-rest.
