FROM grafana/alloy:latest

COPY config.alloy /etc/alloy/config.alloy
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]