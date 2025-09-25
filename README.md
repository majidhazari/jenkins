# jenkins

Deploy Jenkins using Docker

Here’s a production-ready `docker-compose.yml` that follows the **official Jenkins + Docker-in-Docker (dind)** pattern so Jenkins can build Docker images and push them to your registry. It mirrors the current steps from the Jenkins docs and use a custom Jenkins image that includes the Docker CLI and the `docker-workflow` plugin.

## Quick start

1. Pull this repository into a folder, then:

   ```bash
   docker compose build
   docker compose up -d
   ```

2. Open `http://localhost:8080` and complete the setup. To get the unlock password:

   ```bash
   docker exec -it $(docker ps -qf "name=^/jenkins$") \
     cat /var/jenkins_home/secrets/initialAdminPassword
   ```

---

## TLS DinD

1. **Confirm the certs exist** (they’re created automatically by `docker:dind` when `DOCKER_TLS_CERTDIR=/certs` is set):

```bash
# from your host
docker exec -it <jenkins-container> ls -l /certs/client
# expect: ca.pem  cert.pem  key.pem
```

Those files come from the DinD sidecar and are mounted into Jenkins at `/certs/client`. ([Jenkins][1])

2. **Add Docker TLS credentials in Jenkins**

* Jenkins UI → **Manage Jenkins → Credentials → (Global) → Add Credentials**
* **Kind:** *Docker Host Certificate Authentication* (or **X.509 Client Certificate**, depending on plugin/UI)
* Paste file contents from the Jenkins container:

  * **Client Key:** `/certs/client/key.pem`
  * **Client Certificate:** `/certs/client/cert.pem`
  * **Server CA Certificate:** `/certs/client/ca.pem`
* Give it an ID like `docker-tls`. ([Jenkins][2])

3. **Wire the Docker Cloud to use TLS**

* Jenkins UI → **Manage Jenkins → Nodes and Clouds → Configure Clouds → Add a new cloud → Docker**
* **Docker Host URI:** `tcp://docker:2376`
* **Server credentials:** select the credential you created in step 2
* Click **Test Connection** → should succeed.
  This works because 2376 expects **HTTPS with client auth**; the credentials make the plugin speak TLS instead of HTTP. ([Jenkins Plugins][3])

---

## Setting up Jenkins Agent

To configure the Jenkins agent, follow these steps:

1. **Launch Jenkins**:
   Ensure that Jenkins is running. Use the following commands to start Jenkins if it is not already running:

   ```bash
   docker compose up -d
   ```

2. **Retrieve the Linux Docker Node Secret**:
   * Open the Jenkins UI at `http://localhost:8080`.
   * Navigate to **Manage Jenkins → Manage Nodes and Clouds → linux-docker**.
   * Copy the **Secret** value for the `linux-docker` node.

3. **Create the `.env` File**:
   * In the root directory of this project, create a file named `.env`.
   * Add the following line to the `.env` file, replacing `<SECRET>` with the secret value you copied in step 2:

     ```env
     JENKINS_SECRET=<SECRET>
     ```

   Alternatively, you can export the secret as an environment variable in your shell:

   ```bash
   export JENKINS_SECRET=<SECRET>
   ```

This secret will be used by the `jenkins-agent` container to connect to the Jenkins controller.

[1]: https://www.jenkins.io/doc/book/installing/docker/ "Docker"
[2]: https://www.jenkins.io/doc/book/using/using-credentials/ "Using credentials"
[3]: https://plugins.jenkins.io/docker-plugin/ "Docker | Jenkins plugin"
