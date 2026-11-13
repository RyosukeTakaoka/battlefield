#include <metal_stdlib>
using namespace metal;

// 画面全体にかける後処理: 距離の霧(空気遠近法), 色の調整, 周辺を少し暗く.
//
// 霧の式は Tools/blender/preview_course.py の fog_amount と同じ.
// 奥行き(depth)から距離を出すときは, 投影行列の値を使うので,
// RealityKit が奥行きを「手前が 1」で持っていても「手前が 0」で持っていても正しく動く.

struct FogUniforms {
    float4x4 projection;
    float4 fogColor;      // 霧の色(.a は使わない)
    float fogStart;       // 霧が始まる距離(m)
    float fogEnd;         // 霧がいちばん濃くなる距離(m)
    float fogMax;         // 霧の最大の濃さ(0〜1)
    float skyDistance;    // これより遠い(=空のドーム)には霧をかけない
    float vignette;       // 周辺を暗くする強さ
    float saturation;     // 彩度(1 で変えない)
    float flash;          // 雲を抜けたときなどに白く明るくする(0〜1)
    float encodeSRGB;     // 出力の画像が sRGB の数値で持つ形式なら 1
};

static float fogAmount(float dist, constant FogUniforms &u) {
    float t = clamp((dist - u.fogStart) / max(u.fogEnd - u.fogStart, 1.0), 0.0, 1.0);
    float a = (1.0 - exp(-t * t * 3.2)) / (1.0 - exp(-3.2));
    return dist > u.skyDistance ? 0.0 : clamp(a, 0.0, 1.0) * u.fogMax;
}

kernel void paperPlanePostProcess(texture2d<half, access::read> source [[texture(0)]],
                                  depth2d<float, access::read> depth [[texture(1)]],
                                  texture2d<half, access::write> target [[texture(2)]],
                                  constant FogUniforms &u [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    uint w = target.get_width(), h = target.get_height();
    if (gid.x >= w || gid.y >= h) { return; }
    half4 c = source.read(gid);

    // 奥行きの画像は大きさが違うことがあるので, 割合で読む.
    uint2 dg = uint2(float2(gid) * float2(depth.get_width(), depth.get_height()) / float2(w, h));
    float d = depth.read(dg);
    // 投影行列から「カメラからの距離」を出す(列優先: projection[列][行]).
    float denom = d + u.projection[2][2];
    float dist = abs(denom) < 1e-7 ? 1e9 : u.projection[3][2] / denom;
    if (dist < 0.0 || d <= 0.0) { dist = 1e9; }   // 奥の果て(何も無い)

    float3 col = float3(c.rgb);
    float3 fogCol = u.fogColor.rgb;
    float f = fogAmount(dist, u);
    col = mix(col, fogCol, f);

    // 彩度.
    float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = mix(float3(luma), col, u.saturation);

    // 白いもや(雲を抜けたとき).
    col = mix(col, float3(1.0), u.flash);

    // 周辺を少し暗く.
    float2 uv = (float2(gid) + 0.5) / float2(w, h) - 0.5;
    float v = 1.0 - u.vignette * smoothstep(0.35, 0.85, length(uv * float2(1.0, 0.8)) * 1.4);
    col *= v;

    target.write(half4(half3(col), c.a), gid);
}
