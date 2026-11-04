# Installation configuration

`country.yml` is this installation's identity: country, portal name and host, regulator, contacts, mail senders,
credits and time zone. It is read once at start-up by the portal, the harvester and the deployment scripts; a missing
file or a missing required key stops start-up with a message naming the file and the key. Set `NETD_COUNTRY` to read
another file.

`examples/zambia/` holds the configuration of the Zambia National ETD Portal (https://netd.ac.zm), the shipped example.
A new installation copies `examples/<country>/country.yml` to `country.yml` and edits it (manual chapter 7).
