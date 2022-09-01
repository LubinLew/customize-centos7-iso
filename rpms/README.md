# rpms

**You need to resolve rpm dependencies.**


You can try `yumdownloader -x \*i686 -archlist=x86_64,noarch --resolve XXX YYY` in a `centos:latest` docker.

> `--resolve` will not download the packages you have already installed.

If you get a dependency problem when installing the ISO, check the `/tmp/packaging.log` file.
