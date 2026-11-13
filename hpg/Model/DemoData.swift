import Foundation

/// Made-up squeue / sacctmgr / blue_quota / sinfo output in the real formats, for trying the app
/// without logging in (and for the README screenshots). Every group, user and job here is fictional.
enum DemoData {
    static let squeue: String = {
        var lines = [
            "60000101|hpg-b200|llm-finetune-r0|ml4health|ml4health|RUNNING|5:12:40|12:00:00|16|128G|gres/gpu:b200:4|c1004a-s25",
            "60000102|hpg-b200|llm-finetune-r1|ml4health|ml4health|RUNNING|5:10:02|12:00:00|16|128G|gres/gpu:b200:4|c1005a-s25",
            "60000104|hpg-rtx6000|train-vit-b16|ml4health|ml4health|RUNNING|11:31:55|12:00:00|12|96G|gres/gpu:rtx_pro_6000:2|c0907a-s5",
            "60000103|hpg-l4|protein-fold|chenlab|chenlab|RUNNING|1:47:09|8:00:00|8|64G|gres/gpu:l4:2|c0602a-s4",
            "60000099|hpg-default,hpg-milan,hpg-turin|jupyter|chenlab|chenlab|RUNNING|2:03:44|1-00:00:00|4|16G|N/A|c0712a-s3",
            "60000110|hpg-b200,hpg-rtx6000|eval-sweep|ml4health|ml4health|PENDING|0:00|3:00:00|4|32G|gres/gpu:1|(Dependency)",
            "60000111|hpg-b200,hpg-rtx6000|eval-sweep|ml4health|ml4health|PENDING|0:00|3:00:00|4|32G|gres/gpu:1|(Dependency)",
            "60000112|hpg-b200,hpg-rtx6000|eval-sweep|ml4health|ml4health|PENDING|0:00|3:00:00|4|32G|gres/gpu:1|(Dependency)",
            "60000113|hpg-b200,hpg-rtx6000|eval-sweep|ml4health|ml4health|PENDING|0:00|3:00:00|4|32G|gres/gpu:1|(Dependency)",
            "60000120|hpg-b200|llm-eval|ml4health|ml4health|PENDING|0:00|2:00:00|8|64G|gres/gpu:b200:2|(QOSGrpGRES)",
            "60000121|hpg-default|climate-ens-post|climate|climate|PENDING|0:00|4:00:00|4|32G|N/A|(Priority)",
            "60000300|hpg-milan|render-frames|smithlab|smithlab-b|RUNNING|3:20:00|4-00:00:00|32|64G|N/A|c0710a-s1",
            "60000200_[12-39%12]|hpg-default|preprocess-shard|climate|climate-b|PENDING|0:00|6:00:00|16|32G|N/A|(JobArrayTaskLimit)",
        ]
        for i in 0..<12 {
            lines.append("60000200_\(i)|hpg-default|preprocess-shard|climate|climate-b|RUNNING|\(1 + i % 5):\(String(format: "%02d", (i * 13) % 60)):07|6:00:00|16|32G|N/A|c07\(String(format: "%02d", 1 + i % 9))a-s\(3 + i * 2)")
        }
        return lines.joined(separator: "\n")
    }()

    static let allocations = """
    ##ME
    demo
    ##GROUPS
    smithlab chenlab ml4health climate workshop
    ##QOS
    smithlab|cpu=64,gres/gpu=4,mem=500G
    smithlab-b|cpu=576,gres/gpu=0,mem=4500G
    chenlab|cpu=32,gres/gpu=8,mem=250G
    chenlab-b|cpu=288,gres/gpu=0,mem=2250G
    ml4health|cpu=96,gres/gpu=16,mem=750G
    ml4health-b|cpu=864,gres/gpu=0,mem=6750G
    climate|cpu=128,gres/gpu=0,mem=1000G
    climate-b|cpu=1152,gres/gpu=0,mem=9000G
    workshop|cpu=744,gres/gpu=93,mem=5812.50G
    workshop-b|cpu=6696,gres/gpu=0,mem=52312.50G
    ##JOBS
    smithlab alex.r R smithlab cpu=48,mem=360G,node=1,gres/gpu=3
    smithlab alex.r PD smithlab cpu=32,mem=200G,node=1,gres/gpu=2
    smithlab demo R smithlab-b cpu=32,mem=64G,node=1
    chenlab demo R chenlab cpu=8,mem=64G,node=1,gres/gpu=2
    chenlab demo R chenlab cpu=4,mem=16G,node=1
    chenlab mei.w R chenlab cpu=16,mem=120G,node=1,gres/gpu=4
    chenlab omar.h PD chenlab cpu=8,mem=64G,node=1,gres/gpu=2
    ml4health demo R ml4health cpu=16,mem=128G,node=1,gres/gpu=4
    ml4health demo R ml4health cpu=16,mem=128G,node=1,gres/gpu=4
    ml4health demo R ml4health cpu=12,mem=96G,node=1,gres/gpu=2
    ml4health priya.n R ml4health cpu=24,mem=192G,node=1,gres/gpu=4
    ml4health demo PD ml4health cpu=4,mem=32G,node=1,gres/gpu=1
    ml4health demo PD ml4health cpu=4,mem=32G,node=1,gres/gpu=1
    ml4health demo PD ml4health cpu=4,mem=32G,node=1,gres/gpu=1
    ml4health demo PD ml4health cpu=4,mem=32G,node=1,gres/gpu=1
    ml4health demo PD ml4health cpu=8,mem=64G,node=1,gres/gpu=2
    ml4health sam.k PD ml4health cpu=16,mem=128G,node=1,gres/gpu=4
    ml4health sam.k PD ml4health cpu=16,mem=128G,node=1,gres/gpu=4
    climate lena.f R climate cpu=96,mem=720G,node=2
    climate jordan.l R climate-b cpu=256,mem=512G,node=8
    climate demo R climate-b cpu=192,mem=384G,node=9
    climate demo PD climate cpu=4,mem=32G,node=1
    climate demo PD climate-b cpu=16,mem=32G,node=1
    climate demo PD climate-b cpu=16,mem=32G,node=1
    climate demo PD climate-b cpu=16,mem=32G,node=1
    ##QUOTA
    smithlab 3.2T 4T
    chenlab 812G 2T
    ml4health 9.7T 10T
    climate 21.4T 40T
    workshop 1.2G 20T
    ##GPUS
    c0900a-s1 gpu:l4:585(S:0-1) gpu:l4:373(IDX:0) mix
    c0900a-s2 gpu:l4:9(S:0-1) gpu:l4:0(IDX:N/A) drain
    c0901a-s1 gpu:rtx_pro_6000:336(S:0-1) gpu:rtx_pro_6000:330(IDX:0) mix
    c0901a-s2 gpu:rtx_pro_6000:24(S:0-1) gpu:rtx_pro_6000:0(IDX:N/A) drain
    c0902a-s1 gpu:b200:456(S:0-1) gpu:b200:442(IDX:0) mix
    c0902a-s2 gpu:b200:24(S:0-1) gpu:b200:0(IDX:N/A) drain
    """

    /// `getent` + `squeue -u` output for the made-up users in `allocations`.
    static func userJobs(_ user: String) -> String {
        let people: [String: (String, [String])] = [
            "alex.r": ("Alex Rivera", [
                "60001001|hpg-rtx6000|md-sim-membrane|smithlab|smithlab|RUNNING|9:14:22|2-00:00:00|48|360G|gres/gpu:rtx_pro_6000:3|c0908a-s5",
                "60001002|hpg-rtx6000|md-sim-analysis|smithlab|smithlab|PENDING|0:00|12:00:00|32|200G|gres/gpu:rtx_pro_6000:2|(QOSGrpGRES)",
            ]),
            "mei.w": ("Mei Wong", [
                "60002001|hpg-l4|cryo-em-refine|chenlab|chenlab|RUNNING|3:02:51|1-00:00:00|16|120G|gres/gpu:l4:4|c0603a-s2",
            ]),
            "omar.h": ("Omar Haddad", [
                "60003001|hpg-l4|docking-batch|chenlab|chenlab|PENDING|0:00|6:00:00|8|64G|gres/gpu:l4:2|(QOSGrpGRES)",
            ]),
            "priya.n": ("Priya Nair", [
                "60004001|hpg-b200|rlhf-ppo|ml4health|ml4health|RUNNING|7:45:10|1-00:00:00|24|192G|gres/gpu:b200:4|c1006a-s25",
                "60004002|hpg-b200|reward-model|nlp-core|nlp-core|RUNNING|1:12:33|12:00:00|16|128G|gres/gpu:b200:4|c1007a-s25",
                "60004003|hpg-b200|reward-model-eval|nlp-core|nlp-core|PENDING|0:00|2:00:00|8|64G|gres/gpu:b200:2|(Priority)",
            ]),
            "sam.k": ("Sam Kim", [
                "60005001|hpg-b200|pretrain-7b|ml4health|ml4health|PENDING|0:00|4-00:00:00|16|128G|gres/gpu:b200:4|(Resources)",
                "60005002|hpg-b200|pretrain-7b|ml4health|ml4health|PENDING|0:00|4-00:00:00|16|128G|gres/gpu:b200:4|(Priority)",
            ]),
            "lena.f": ("Lena Fischer", [
                "60006001|hpg-default|wrf-ensemble|climate|climate|RUNNING|14:20:05|3-00:00:00|96|720G|N/A|c0[702-703]a-s11",
            ]),
            "jordan.l": ("Jordan Lee", (0..<8).map { i in
                "60007000_\(i)|hpg-default|era5-regrid|climate|climate-b|RUNNING|2:\(String(format: "%02d", 10 + i * 4)):41|8:00:00|32|64G|N/A|c06\(String(format: "%02d", 10 + i))a-s\(i + 4)"
            }),
            "demo": ("Demo User", squeue.components(separatedBy: "\n")),
        ]
        guard let (name, jobs) = people[user] else { return "\n##JOBS\n" }
        return name + "\n##JOBS\n" + jobs.joined(separator: "\n")
    }
}
