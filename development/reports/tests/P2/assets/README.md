# P2 临时人物资源导入

负责人允许从 CityDefenseDot 临时复用资源。源目录为 `D:/work/game/CityDefenseDot/presentation/assets/polyfork/`。本次只在临时工程复制、导入和实例化将领、枪兵、弩兵 GLB，每个角色均读取出 22 根骨骼、12 个蒙皮网格和各含 22 条轨道的 Idle、Walk、Run。Godot 导入和运行均退出 0。[逐件 SHA-256 和实测](import.txt)

重跑命令：`python run.py --godot <Godot-console> --source <polyfork目录>`。动作和骑乘动画、真实混合战场性能尚未由此验证。三件模型在 CityDefenseDot 原有的改动包含阵营服色、外观比例或动画绑定，本次导入保持 GLB 原字节。作为临时资源使用时随包保留作者、原作链接、许可及后续改动。正式原创资产数量另行统计。[Polyfork 官方许可](https://polyfork.dev/licensing) · [资源集](https://polyfork.dev/kit/three-kingdoms-settlements-a-1e817b) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

| 模型 | 作者与原作 |
|---|---|
| general.glb | Polyfork · [General](https://polyfork.dev/asset/general-2ddbba) |
| spear_soldier.glb | Polyfork · [Spear Soldier](https://polyfork.dev/asset/spear-soldier-dcfb4b) |
| crossbowman.glb | Polyfork · [Crossbowman](https://polyfork.dev/asset/crossbowman-4bf6b1) |

骑兵采用 Quaternius 发布的 CC0 Horse 作为临时候选，模型 1,108,124 字节。Godot 实际加载出一具 50 骨骨架和一个蒙皮网格，Idle、Walk、Gallop 均可播放，各 48 条轨道。下载内容留在本地 out 缓存；生产内容按 VIS 任务再接入。复跑导入命令附加 `--horse <horse.glb>`。[作者的许可与原包](https://quaternius.itch.io/lowpoly-animated-animals) · [模型发布页](https://poly.pizza/m/qvTrSG9pZF) · [GLB](https://static.poly.pizza/d37dbc87-ca61-4b2c-a2da-d2f0c4240bef.glb) · [导入结果和 SHA-256](horse-import.txt)
