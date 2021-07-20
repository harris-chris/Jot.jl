# Troubleshooting

#### Getting `IOError(Base.IOError("read: connection reset by peer (ECONNRESET)", -104) during request(http://localhost:9000/2015-03-31/functions/function/invocations))` when testing a local image
This is a problem with the `containerd` runtime, used by the Docker daemon. Restarting the service should fix this (it may refuse to shut down when being restarted, in which case it will eventually time out). With systemd this can be done with `systemctl restart containerd`. Restarting the local machine will also work.
