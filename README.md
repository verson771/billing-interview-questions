# README

The repository contains a simplified app for a billing service.
Compute clusters send a report to S3 per virtual machine on every change / 24 hours.
The billing service fetches reports from S3 and process them.
The billing service processing will create events of changes for virtual_machines that can be later used to create invoices.
In this demo we will use file based reports and not S3, but please assume the production service will use S3.

DB schema

### compute_cluster

uuid
name

### virtual_machine

created_at
updated_at
status
deleted_at
deleted
uuid
compute_cluster_id

### event

created_at
vm_id
event_type

