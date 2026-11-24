shader_type spatial;
render_mode unshaded;
uniform float tip_sway_m=.48;
uniform float sway_speed=.72;
uniform bool vertex_snap=false;
varying float h;
varying float rank;
varying float facet;
void vertex(){
 vec3 pos=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 h=pos.y;rank=INSTANCE_CUSTOM.r;facet=dot(normalize(MODEL_NORMAL_MATRIX*NORMAL),normalize(vec3(.7,.15,.6)));
 vec3 sway=vec3(1.,0.,.25)*tip_sway_m*pow(clamp(VERTEX.y+.5,0.,1.),2.)*sin(TIME*sway_speed+dot(pos.xz,vec2(.12,.085)));
 VERTEX+=inverse(mat3(MODEL_MATRIX))*sway;
 vec4 clip=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.);
 if(vertex_snap && clip.w>.01){clip.xy=round(clip.xy/clip.w*180.)/180.*clip.w;}
 POSITION=clip;
}
void fragment(){
 vec3 body=mix(vec3(.025,.043,.035),vec3(.095,.13,.10),step(.18,facet));
 ALBEDO=mix(body,vec3(.15,.18,.14),step(.925,fract(h*1.65)))*mix(1.,.15,rank);
}
