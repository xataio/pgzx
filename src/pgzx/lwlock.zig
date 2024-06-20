//! Provides wrappers and helpers for Postgres LWLocks.
//!
//! NOTE:
//! The global locks like `AddinShmemInitLock` are not directly accessible from
//! the generated C bindings. We provide wrapper functions for them here.

const pg = @import("pgzx_pgsys");

// access `MainLWLockArray`.
//
// We use a function because the Zig compiler currently complains that it can
// access the ID only at runtime.
inline fn mainLock(id: usize) fn () *pg.LWLock {
    return struct {
        fn call() *pg.LWLock {
            return &pg.MainLWLockArray[id].lock;
        }
    }.call;
}

// names and IDs takend from lwlocknames.txt
pub const ShmemIndex = mainLock(1);
pub const OidGen = mainLock(2);
pub const XidGen = mainLock(3);
pub const ProcArray = mainLock(4);
pub const SInvalRead = mainLock(5);
pub const SInvalWrite = mainLock(6);
pub const WALBufMapping = mainLock(7);
pub const WALWrite = mainLock(8);
pub const ControlFile = mainLock(9);
pub const XactSLRU = mainLock(11);
pub const SubtransSLRU = mainLock(12);
pub const MultiXactGen = mainLock(13);
pub const MultiXactOffsetSLRU = mainLock(14);
pub const MultiXactMemberSLRU = mainLock(15);
pub const RelCacheInit = mainLock(16);
pub const CheckpointerComm = mainLock(17);
pub const TwoPhaseState = mainLock(18);
pub const TablespaceCreate = mainLock(19);
pub const BtreeVacuum = mainLock(20);
pub const AddinShmemInit = mainLock(21);
pub const Autovacuum = mainLock(22);
pub const AutovacuumSchedule = mainLock(23);
pub const SyncScan = mainLock(24);
pub const RelationMapping = mainLock(25);
pub const NotifySLRU = mainLock(26);
pub const NotifyQueue = mainLock(27);
pub const SerializableXactHash = mainLock(28);
pub const SerializableFinishedList = mainLock(29);
pub const SerializablePredicateList = mainLock(30);
pub const SerialSLRU = mainLock(31);
pub const SyncRep = mainLock(32);
pub const BackgroundWorker = mainLock(33);
pub const DynamicSharedMemoryControl = mainLock(34);
pub const AutoFile = mainLock(35);
pub const ReplicationSlotAllocation = mainLock(36);
pub const ReplicationSlotControl = mainLock(37);
pub const CommitTsSLRU = mainLock(38);
pub const CommitTs = mainLock(39);
pub const ReplicationOrigin = mainLock(40);
pub const MultiXactTruncation = mainLock(41);
pub const LogicalRepWorker = mainLock(43);
pub const XactTruncation = mainLock(44);
pub const WrapLimitsVacuum = mainLock(46);
pub const NotifyQueueTail = mainLock(47);
pub const WaitEventExtension = mainLock(48);
pub const WALSummarizer = mainLock(49);
pub const DSMRegistry = mainLock(50);
pub const InjectionPoint = mainLock(51);
