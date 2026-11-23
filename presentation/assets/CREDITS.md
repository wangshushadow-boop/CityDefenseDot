# 双城争夺战 · 场景与角色资源

## Three Kingdoms Settlements

以下免费低多边形 GLB 的作者为 **Polyfork**。本项目选择 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 使用和随游戏分发。来源见[资源套件](https://polyfork.dev/kit/three-kingdoms-settlements-a-1e817b)及[作者的许可说明](https://polyfork.dev/licensing)。

| 本地模型 | 原始作品 | 本项目的调整 |
| --- | --- | --- |
| `polyfork/general.glb` | [General](https://polyfork.dev/asset/general-2ddbba) | 应用阵营服色、绑定待机和移动动画 |
| `polyfork/spear_soldier.glb` | [Spear Soldier](https://polyfork.dev/asset/spear-soldier-dcfb4b) | 作为步兵外观，应用阵营色与角色比例 |
| `polyfork/crossbowman.glb` | [Crossbowman](https://polyfork.dev/asset/crossbowman-4bf6b1) | 作为远程兵外观，应用阵营色与角色比例 |
| `polyfork/city_gate.glb` | [City Gate](https://polyfork.dev/asset/city-gate-77d012) | 压缩门楼两翼网格并调整法线，保留门轴，适配四米门洞 |
| `polyfork/camp_gate.glb` | [Camp Gate](https://polyfork.dev/asset/camp-gate-2de13f) | 作为侧门，调整比例、朝向与门扇开闭 |
| `polyfork/city_wall_run.glb` | [City Wall Run](https://polyfork.dev/asset/city-wall-run-1f4c31) | 分段拼接并按地形调整位置 |
| `polyfork/raised_granary.glb` | [Raised Granary](https://polyfork.dev/asset/raised-granary-287b40) | 按占领区调整比例与位置 |
| `polyfork/faction_banner_pole.glb` | [Faction Banner Pole](https://polyfork.dev/asset/faction-banner-pole-39835b) | 旗面使用本方阵营色 |

导入脚本为模型启用原始顶点色，并设置角色动画循环。

## 界面画稿

部署与结算共用的[双城河谷背景](../ui/river_pass.png)由 ImageGen 为本项目生成。军旗标记和沙盘直接由 Godot 绘制。

## 参考工程的野外资源

`meadow/pine.obj`、`broadleaf.obj`、`grass_clump.obj` 和 `boulder.obj` 取自用户指定的本机项目 `CityDefenseGodot/levels/meadow/`。本工程复用其网格与植被 UV 约定，按双城布局重新布置树木和石群，并为当前地形配置地表、河水及植被着色。这四个网格的来源独立于上述 Polyfork 许可。
