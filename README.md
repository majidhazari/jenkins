# jenkins

Deploy Jenkins using Docker

# TLS DinD

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

[1]: https://www.jenkins.io/doc/book/installing/docker/ "Docker"
[2]: https://www.jenkins.io/doc/book/using/using-credentials/ "Using credentials"
[3]: https://plugins.jenkins.io/docker-plugin/ "Docker | Jenkins plugin"
