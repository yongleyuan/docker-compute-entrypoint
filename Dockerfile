########
# base #
########

# Specify the opensciencegrid/software-base image tag
ARG BASE_YUM_REPO=release

FROM opensciencegrid/software-base:3.5-el7-$BASE_YUM_REPO AS base
LABEL maintainer "OSG Software <help@opensciencegrid.org>"

# previous arg has gone out of scope
ARG BASE_YUM_REPO=release

# Ensure that the 'condor' UID/GID matches across containers
RUN groupadd -g 64 -r condor && \
    useradd -r -g condor -d /var/lib/condor -s /sbin/nologin \
      -u 64 -c "Owner of HTCondor Daemons" condor

RUN if [[ $BASE_YUM_REPO = release ]]; then \
       yumrepo=osg-upcoming; else \
       yumrepo=osg-upcoming-$BASE_YUM_REPO; fi && \
    yum install -y --enablerepo=$yumrepo \
                   osg-ce-bosco \
                   # FIXME: avoid htcondor-ce-collector conflict
                   htcondor-ce \
                   htcondor-ce-view \
                   git \
                   openssh-clients \
                   sudo \
                   wget \
                   certbot \
                   perl-LWP-Protocol-https \
                   # ^^^ for fetch-crl, in the rare case that the CA forces HTTPS
                   patch && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY base/etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY base/etc/condor-ce/config.d/* /usr/share/condor-ce/config.d/
COPY base/usr/local/bin/* /usr/local/bin/
COPY base/etc/supervisord.d/* /etc/supervisord.d/

# do the bad thing of overwriting the existing cron job for fetch-crl
COPY base/etc/cron.d/fetch-crl /etc/cron.d/fetch-crl
RUN chmod 644 /etc/cron.d/fetch-crl

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
COPY base/overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics

# Workaround BatchRuntime expresion bug (HTCONDOR-506)
COPY base/overrides/HTCONDOR-506.evalset-batchruntime.patch /tmp
RUN patch -d / -p0 < /tmp/HTCONDOR-506.evalset-batchruntime.patch
RUN if ! grep -qi 'EVALSET.*BatchRuntime.*maxWallTime' /usr/share/condor-ce/config.d/01-ce-router-defaults.conf; then  \
        echo "HTCONDOR-506 (BatchRuntime) fix missing!";  \
        exit 1;  \
    fi

#################
# osg-ce-condor #
#################

FROM base AS osg-ce-condor
ARG BASE_YUM_REPO=release
LABEL maintainer "OSG Software <help@opensciencegrid.org>"
LABEL name "osg-ce-condor"

RUN if [[ $BASE_YUM_REPO = release ]]; then \
       yumrepo=osg-upcoming; else \
       yumrepo=osg-upcoming-$BASE_YUM_REPO; fi && \
     yum install -y --enablerepo=$yumrepo \
                   osg-ce-condor && \
    yum clean all && \
    rm -rf /var/cache/yum/

COPY osg-ce-condor/etc/osg/image-config.d/* /etc/osg/image-config.d/
COPY osg-ce-condor/etc/condor/config.d/* /etc/condor/config.d/
COPY osg-ce-condor/usr/local/bin/* /usr/local/bin/
COPY osg-ce-condor/etc/supervisord.d/* /etc/supervisord.d/

#############
# hosted-ce #
#############

FROM base AS hosted-ce
LABEL maintainer "OSG Software <help@opensciencegrid.org>"
LABEL name "hosted-ce"

ARG BASE_YUM_REPO=release

RUN if [[ $BASE_YUM_REPO = release ]]; then \
       yumrepo=osg-upcoming; else \
       yumrepo=osg-upcoming-$BASE_YUM_REPO; fi && \
    yum install -y --enablerepo=$yumrepo \
                   osg-ce-bosco && \
    rm -rf /var/cache/yum/

COPY hosted-ce/30-remote-site-setup.sh /etc/osg/image-config.d/

# HACK: override condor_ce_jobmetrics from SOFTWARE-4183 until it is released in
# HTCondor-CE.
COPY hosted-ce/overrides/condor_ce_jobmetrics /usr/share/condor-ce/condor_ce_jobmetrics

# Use "ssh -q" in bosco_cluster until the chang has been upstreamed to condor
COPY hosted-ce/overrides/ssh_q.patch /tmp
RUN patch -d / -p0 < /tmp/ssh_q.patch

# Enable bosco_cluster xtrace
COPY hosted-ce/overrides/bosco_cluster_xtrace.patch /tmp
RUN patch -d / -p0 < /tmp/bosco_cluster_xtrace.patch

# FIXME: Remove this check after a successful build
# Don't copy the SSH key (HTCONDOR-270)
RUN if ! fgrep -q -- '--copy-ssh-key' /usr/bin/bosco_cluster; then  \
        echo "HTCONDOR-270 (skip SSH key copy) fix missing!";  \
        exit 1;  \
    fi

# FIXME: Remove this check after a successful build
# Add Scientific Linux OS detection to bosco_cluster (HTCONDOR-503)
RUN if ! fgrep '(rhel|centos|scientific)' /usr/bin/bosco_cluster; then  \
        echo "HTCONDOR-503 (SL support) fix missing!";  \
        exit 1;  \
    fi

COPY hosted-ce/ssh-to-login-node /usr/local/bin

# Set up Bosco override dir from Git repo (SOFTWARE-3903)
# Expects a Git repo with the following directory structure:
#     RESOURCE_NAME_1/
#         bosco_override/
#         ...
#     RESOURCE_NAME_2/
#         bosco_override/
#         ...
#     ...
COPY hosted-ce/bosco-override-setup.sh /usr/local/bin
