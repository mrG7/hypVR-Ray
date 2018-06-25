//-------------------------------------------------------
//Hyperbolic Math functions
//-------------------------------------------------------
float cosh(float x){
  float eX = exp(x);
  return (0.5 * (eX + 1.0/eX));
}
float sinh(float x){
  float eX = exp(x);
  return (0.5 * (eX - 1.0/eX));
}
float asinh(float x){
  return log(x + sqrt(x*x+1.0));
}

//-------------------------------------------------------
//Hyperboloid Functions
//-------------------------------------------------------

vec4 projectToKlein(vec4 v){
  return v/v.w;
}

vec4 pointOnGeodesic(vec4 u, vec4 vPrime, float dist){ // get point on
  // hyperboloid at distance dist on the geodesic from u through v
  return u*cosh(dist) + vPrime*sinh(dist);
}

vec4 tangentVectorOnGeodesic(vec4 u, vec4 vPrime, float dist){
  // note that this point has geometryDot with itself of -1, so it is on other hyperboloid
  return u*sinh(dist) + vPrime*cosh(dist);
}

vec4 pointOnGeodesicAtInfinity(vec4 u, vec4 vPrime){ // returns point on the light
  // cone intersect Klein model corresponding to the point at infinity on the
  // geodesic through u and v
  return projectToKlein(u + vPrime);
}

//---------------------------------------------------------------------
//Raymarch Primitives
//---------------------------------------------------------------------

float sphereHSDF(vec4 samplePoint, vec4 center, float radius){
  return geometryDistance(samplePoint, center) - radius;
}

// A horosphere can be constructed by offseting from a standard horosphere.
// Our standard horosphere will have a center in the direction of lightPoint
// and go through the origin. Negative offsets will "shrink" it.
float horosphereHSDF(vec4 samplePoint, vec4 lightPoint, float offset){
  return log(-geometryDot(samplePoint, lightPoint)) - offset;
}

float geodesicPlaneHSDF(vec4 samplePoint, vec4 dualPoint, float offset){
  return asinh(-geometryDot(samplePoint, dualPoint)) - offset;
}

float geodesicCylinderHSDFplanes(vec4 samplePoint, vec4 dualPoint1, vec4 dualPoint2, float radius){
  // defined by two perpendicular geodesic planes
  float dot1 = -geometryDot(samplePoint, dualPoint1);
  float dot2 = -geometryDot(samplePoint, dualPoint2);
  return asinh(sqrt(dot1*dot1 + dot2*dot2)) - radius;
}

float geodesicCylinderHSDFends(vec4 samplePoint, vec4 lightPoint1, vec4 lightPoint2, float radius){
  // defined by two light points (at ends of the geodesic) whose geometryDot is 1
  return acosh(sqrt(2.0*-geometryDot(lightPoint1, samplePoint)*-geometryDot(lightPoint2, samplePoint))) - radius;
}

float geodesicCubeHSDF(vec4 samplePoint, vec4 dualPoint0, vec4 dualPoint1, vec4 dualPoint2, vec3 offsets){
  float plane0 = max(abs(geodesicPlaneHSDF(samplePoint, dualPoint0, 0.0))-offsets.x,0.0); 
  float plane1 = max(abs(geodesicPlaneHSDF(samplePoint, dualPoint1, 0.0))-offsets.y,0.0); 
  float plane2 = max(abs(geodesicPlaneHSDF(samplePoint, dualPoint2, 0.0))-offsets.z,0.0);
  return sqrt(plane0*plane0+plane1*plane1+plane2*plane2) - 0.01; 
} 