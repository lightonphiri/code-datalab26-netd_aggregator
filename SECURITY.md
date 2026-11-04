# Security policy

Please report a security problem privately, not in a public issue: email lighton.phiri@unza.ac.zm with "NETD security" in the subject, a description, and the steps to reproduce it. You will get an acknowledgement within a week.

Supported versions: the latest release tag and `main`. Installations run their own servers; the Zambia National ETD Portal (https://netd.ac.zm) is maintained by the DataLab Research Group.

Design notes relevant to security: the admin panel has no public sign-up (accounts are created on the server), sessions expire after 2 hours idle or 12 hours in total, the REST API and OAI-PMH provider are read-only and rate-limited, and secrets live in `/opt/netd/portal.env`, outside the repository.
