FROM openresty/openresty:centos
MAINTAINER youyu "iihelpcc@gmail.com"
USER root
COPY ./ /var/feijiang
ENV RUN_MODE prod
EXPOSE 9999
RUN yum -y update && \
	yum -y install gcc && \
	yum -y install pcre-devel && \
	luarocks install lrexlib-pcre
	
RUN cd /var/feijiang && \
	mv conf/nginx_${RUN_MODE}.conf conf/nginx.conf && \
	mkdir -p logs && \
	mkdir -p tmp
CMD ["/usr/bin/openresty", "-g", "daemon off;", "-p", "/var/feijiang/"]