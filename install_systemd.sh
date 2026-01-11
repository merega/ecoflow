#!/usr/bin/env sh

cp ./ecoflow-ac-notify.service /etc/systemd/system/
cp ./ecoflow-ac-notify.timer /etc/systemd/system/

mkdir /srv/ecoflow
cp ./* /srv/ecoflow

systemctl daemon-reload
systemctl enable --now ecoflow-ac-notify.timer
