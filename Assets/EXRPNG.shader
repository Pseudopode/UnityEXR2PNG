Shader "Custom/EXRPNG" {
	Properties{
	   _MainTex("Texture Image", 2D) = "white" {}
	}
		SubShader{
		   Pass {
			  CGPROGRAM

			  #pragma vertex vert  
			  #pragma fragment frag 

			  uniform sampler2D _MainTex;

			 struct vertexInput {
				float4 vertex : POSITION;
				float4 texcoord : TEXCOORD0;
			 };
			 struct vertexOutput {
				float4 pos : SV_POSITION;
				float4 tex : TEXCOORD0;
			 };

			 vertexOutput vert(vertexInput input)
			 {
				vertexOutput output;

				output.tex = input.texcoord;
				output.pos = UnityObjectToClipPos(input.vertex);
			 return output;
			}

			 float3 s_left(float3 pixel) {
				 // simulate shifting left 8 bits:
				 return pixel * 256;
			 }

			 float3 s_right(float3 pixel) {
				 // simulate shifting right 8 bits:
				 return floor(pixel * .00390625);
			 }

			 inline float4 EncodeFloatRGBA(float v)
			 {
				 float4 kEncodeMul = float4(1.0, 255.0, 65025.0, 16581375.0);
				 float kEncodeBit = 1.0 / 255.0;
				 float4 enc = kEncodeMul * v;
				 enc = frac(enc);
				 enc -= enc.yzww * kEncodeBit;
				 return enc;
			 }

			 inline float DecodeFloatRGBA(float4 enc)
			 {
				 float4 kDecodeDot = float4(1.0, 1 / 255.0, 1 / 65025.0, 1 / 160581375.0);
				 return dot(enc, kDecodeDot);
			 }

			 inline float2 EncodeFloatRG(float v)
			 {
				 float2 kEncodeMul = float2(1.0, 255.0);
				 float kEncodeBit = 1.0 / 255.0;
				 float2 enc = kEncodeMul * v;
				 enc = frac(enc);
				 enc.x -= enc.y * kEncodeBit;
				 return enc;
			 }
			 inline float DecodeFloatRG(float2 enc)
			 {
				 float2 kDecodeDot = float2(1.0, 1 / 255.0);
				 return dot(enc, kDecodeDot);
			 }

			 float invLerp(float from, float to, float value) {
				 return value - from;
			 }
			 float remap(float origFrom, float origTo, float targetFrom, float targetTo, float value) {
				 float rel = invLerp(origFrom, origTo, value);
				 return lerp(targetFrom, targetTo, rel);
			 }

			 float Decode16(in float2 pack)
			 {
				 float value = dot(pack, 1.0 / float2(1.0, 256.0));
				 return value * (256.0) / (256.0 - 1.0);
			 }

			 float unpack(float2 value)
			 {
				 const float2 bit_shift = float2(1.0, 1.0 / 256.0);
				 float unpacked_val = dot(value, bit_shift);
				 return unpacked_val;
			 }

			 //http://blogs.perl.org/users/rurban/2012/09/reading-binary-floating-point-numbers-numbers-part2.html
			 //sign    1 bit  15
			 //exp     5 bits 14 - 10     bias 15
			 //frac   10 bits 9 - 0
			 /*float half_to_float(float val)
			 {
				 float sign = val && 0x00000000000000001000000000000000;
				 float fraction = val && 0x00000000000000001000000000000000;

				 return (-1)**sign * (1 + fraction / 2 * *10) * 2 * *(exp - 15);
			 }*/

			 float decode(float2 c) {
				 float v = 0.0;

				 int ix = int(c.x*255.); // 1st byte: 1 bit signum, 4 bits exponent, 3 bits mantissa (MSB)
				 int iy = int(c.y*255.);	// 2nd byte: 8 bit mantissa (LSB)

				 int s = (c.x >= 0.5) ? 1 : -1;
				 ix = (s > 0) ? ix - 128 : ix; // remove the signum bit from exponent
				 int iexp = ix / 8; // cut off the last 3 bits of the mantissa to select the 4 exponent bits
				 int msb = ix - iexp * 8;	// subtract the exponent bits to select the 3 most significant bits of the mantissa

				 int norm = (iexp == 0) ? 0 : 2048; // distinguish between normalized and subnormalized numbers
				 int mantissa = norm + msb * 256 + iy; // implicite preceding 1 or 0 added here
				 norm = (iexp == 0) ? 1 : 0; // normalization toggle
				 float exponent = pow(2.0, float(iexp + norm) - 16.0); // -5 for the the exponent bias from 2^-5 to 2^10 plus another -11 for the normalized 12 bit mantissa 
				 v = float(s * mantissa) * exponent;

				 return (1 + mantissa / pow(2,10)) * pow(2,(exponent - 15));

				 return v;
			 }

			 float2 encode(float v) {
				 float2 c = float2(0.0,0.0);

				 int signum = (v >= 0.) ? 128 : 0;
				 v = abs(v);
				 int exponent = 15;
				 float limit = 1024.; // considering the bias from 2^-5 to 2^10 (==1024)
				 for (int exp = 15; exp > 0; exp--) {
					 if (v < limit) {
						 limit /= 2.;
						 exponent--;
					 }
				 }

				 float rest;
				 if (exponent == 0) {
					 rest = v / limit / 2.;		// "subnormalize" implicite preceding 0. 
				 }
				 else {
					 rest = (v - limit) / limit;	// normalize accordingly to implicite preceding 1.
				 }

				 int mantissa = int(rest * 2048.);	// 2048 = 2^11 for the (split) 11 bit mantissa
				 int msb = mantissa / 256;		// the most significant 3 bits go into the lower part of the first byte
				 int lsb = mantissa - msb * 256;		// there go the other 8 bit of the lower significance

				 c.x = float(signum + exponent * 8 + msb) / 255.;	// color normalization for texture2D
				 c.y = float(lsb) / 255.;

				 if (v >= 2048.) {
					 c.y = 1.;
				 }

				 return c;
			 }

			 float4 encode2(float2 v) {
				 return float4(encode(v.x), encode(v.y));
			 }

			 /*float getNthBit(float2 v, int bit) {
				 float t = bit < 16 ? v[0] : v[1];
				 int b = bit < 16 ? bit : bit - 16;
				 return fmod(floor((t + 0.5) / pow(2.0, float(b))), 2.0);
			 }*/

			 float getNthBit(float v, int bit) {
				 return fmod(floor((v + 0.5) / pow(2.0, float(bit))), 2.0);
			 }

			 float unpack8BitVec2IntoFloat(float2 v, float min, float max) {
				 float zeroTo16Bit = v.x + v.y * 256.0;
				 float zeroToOne = zeroTo16Bit / 256.0 / 255.0;
				 return zeroToOne * (max - min) + min;
			 }

			 /*float4 EncodeFloatRGBA(float v)
			 {
				 float4 enc = float4(1.0, 255.0, 65025.0, 16581375.0) * v;
			 }*/

			 float f16tof32(uint val)
			 {
				 uint sign = (val & 0x8000u) << 16;
				 int exponent = int((val & 0x7C00u) >> 10);
				 uint mantissa = val & 0x03FFu;
				 float f32 = 0.0;
				 if (exponent == 0)
				 {
					 if (mantissa != 0u)
					 {
						 const float scale = 1.0 / (1 << 24);
						 f32 = scale * mantissa;
					 }
				 }
				 else
				 {
					 exponent -= 15;
					 float scale;
					 if (exponent < 0)
					 {
						 // The negative unary operator is buggy on OSX.
						 // Work around this by using abs instead.
						 scale = 1.0 / (1 << abs(exponent));
					 }
					 else
					 {
						 scale = 1 << exponent;
					 }
					 float decimal = 1.0 + float(mantissa) / float(1 << 10);
					 f32 = scale * decimal;
				 }

				 if (sign != 0u)
				 {
					 f32 = -f32;
				 }

				 return f32;
			 }

			 float2 EncodeRangeV2(in float value, in float minVal, in float maxVal)
			 {
				 value = clamp((value - minVal) / (maxVal - minVal), 0.0, 1.0);
				 value *= (256.0*256.0 - 1.0) / (256.0*256.0);
				 float3 encode = frac(value * float3(1.0, 256.0, 256.0*256.0));
				 return encode.xy - encode.yz / 256.0 + 1.0 / 512.0;
			 }

			 float DecodeRangeV2(in float2 pack, in float minVal, in float maxVal)
			 {
				 float value = dot(pack, 1.0 / float2(1.0, 256.0));
				 value *= (256.0*256.0) / (256.0*256.0 - 1.0);
				 return lerp(minVal, maxVal, value);
			 }


			float4 frag(vertexOutput input) : COLOR
			{
				float4 PNG =  tex2D(_MainTex, input.tex.xy);

				float png_R = tex2D(_MainTex, input.tex.xy).r;
				float png_G = tex2D(_MainTex, input.tex.xy).g;
				float png_B = tex2D(_MainTex, input.tex.xy).b;
				float png_A = tex2D(_MainTex, input.tex.xy).a;

				//float R = (png_R * 2 + png_G)/2;
				//float G = (png_B * 2 + png_A)/2;
				/*float R = (png_R * 256 + png_G)/256;
				float G = (png_B * 256 + png_A)/256;*/
				float R = Decode16(PNG.rg);
				float G = Decode16(PNG.ba);

				//float R_half16 = half_to_float(R);
				//float G_half16 = half_to_float(G);

				float R_half16 = decode(PNG.rg);
				float G_half16 = decode(PNG.ba);

				/*float R = (png_R * 256 + png_G) / 256;
				float G = (png_B * 256 + png_A) / 256;*/
				//float G = 0;
				float B = 0;

				float4 outputColor = float4(R_half16, G_half16, B, 1);

				float2 test = EncodeRangeV2(1.0,0.0,1.0);
				//test = EncodeFloatRG(0.9999999);
				float test3 = decode(test);
				float4 testRGBA = EncodeFloatRGBA(0.9999);

				uint y = (PNG.g);
				uint x = (PNG.r);

				outputColor.r = DecodeRangeV2(PNG.gr, 0,1);
				outputColor.g = DecodeRangeV2(PNG.ab, 0, 1);
				outputColor.b = 0;
				outputColor.a = 1;

				//outputColor.r = remap(0, 1, 0, 2, png_R);

				return outputColor;

			}

			ENDCG
			}
	}
		Fallback "Unlit/Texture"
}