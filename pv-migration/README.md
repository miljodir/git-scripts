Scripts in this folder were used for migrating AKS PV's between regions. Velero did not (and maybe still deos not) support this at the time.

The reason for putting the scripts at this point in time is due to migration of data between storageclasses. This may require the use of snapshots and manual creation of PV's + PVC's.
