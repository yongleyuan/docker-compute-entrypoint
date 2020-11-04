# Specify the opensciencegrid/software-base image tag
ARG SW_BASE_TAG=fresh

FROM opensciencegrid/software-base:$SW_BASE_TAG

LABEL maintainer "OSG Software <help@opensciencegrid.org>"

RUN yum install -y --enablerepo=osg-minefield \
                   --enablerepo=osg-upcoming-minefield \
                   osg-ce-bosco \
                   git \
                   openssh-clients \
                   sudo \
                   wget \
                   certbot \
                   patch && \
   # Separate CE View installation to work around Yum depsolving fail
   yum install -y --enablerepo=osg-minefield \
                   htcondor-ce-view && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY etc/condor-ce/config.d/* /usr/share/condor-ce/config.d/
COPY usr/local/bin/* /usr/local/bin/
COPY etc/supervisord.d/* /etc/supervisord.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
ADD etc/cron.d/fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
COPY overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics
