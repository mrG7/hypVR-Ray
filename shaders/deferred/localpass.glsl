#version 300 es

//--------------------------------------------
//Global Constants
//--------------------------------------------
const int MAX_MARCHING_STEPS = 127;
const float MIN_DIST = 0.0;
const float EPSILON = 0.0001;
const vec4 ORIGIN = vec4(0,0,0,1);
//--------------------------------------------
//Global Variables
//--------------------------------------------
out vec4 out_FragColor;
vec4 sampleEndPoint = vec4(1, 1, 1, 1);
vec4 sampleTangentVector = vec4(1, 1, 1, 1);
vec4 N = ORIGIN; //normal vector
vec4 globalLightColor = ORIGIN;
int hitWhich = 0;
//-------------------------------------------
//Translation & Utility Variables
//--------------------------------------------
uniform int isStereo;
uniform vec2 screenResolution;
uniform float fov;
uniform mat4 invGenerators[6];
uniform mat4 currentBoost;
uniform mat4 stereoBoosts[2];
uniform mat4 cellBoost; 
uniform mat4 invCellBoost;
uniform int maxSteps;
uniform float maxDist;
//--------------------------------------------
//Lighting Variables & Global Object Variables
//--------------------------------------------
uniform vec4 lightPositions[4];
uniform vec4 lightIntensities[6]; //w component is the light's attenuation -- 6 since we need controllers
uniform int attnModel;
uniform bool renderShadows[2];
uniform float shadSoft;
uniform sampler2D tex;
uniform int controllerCount; //Max is two
uniform mat4 controllerBoosts[2];
uniform mat4 globalObjectBoost;
uniform float globalObjectRadius;
//--------------------------------------------
//Scene Dependent Variables
//--------------------------------------------
uniform vec4 halfCubeDualPoints[3];
uniform float halfCubeWidthKlein;
uniform float tubeRad;
uniform vec4 cellPosition;
uniform float cellSurfaceOffset;
uniform vec4 vertexPosition;
uniform float vertexSurfaceOffset;

// These are the planar mirrors of the fundamental simplex in the Klein (or analagous) model.
// Order is mirrors opposite: vertex, edge, face, cell.
// The xyz components of a vector give the unit normal of the mirror. The sense will be that the normal points to the outside of the simplex.
// The w component is the offset from the origin.
uniform bool useSimplex;
uniform vec4 simplexMirrorsKlein[4];
uniform vec4 simplexDualPoints[4];

// The type of cut (1=sphere, 2=horosphere, 3=plane) for the vertex opposite the fundamental simplex's 4th mirror.
// These integers match our values for the geometry of the honeycomb vertex figure.
// We'll need more of these later when we support more symmetry groups.
uniform int cut1;
uniform int cut4;

//Raymarch Functions
float unionSDF(float d1, float d2){
  return min(d1, d2);
}

//--------------------------------------------------------------------
// Generalized Functions
//--------------------------------------------------------------------

vec4 geometryNormalize(vec4 v, bool toTangent);
vec4 geometryDirection(vec4 u, vec4 v);
vec4 geometryFixDirection(vec4 u, vec4 v, mat4 fixMatrix);
float geometryDot(vec4 u, vec4 v);
float geometryDistance(vec4 u, vec4 v);
float geometryNorm(vec4 v){
  return sqrt(abs(geometryDot(v,v)));
}

vec4 pointOnGeodesic(vec4 u, vec4 vPrime, float dist);
bool isOutsideCell(vec4 samplePoint, out mat4 fixMatrix);

//--------------------------------------------------------------------
// Generalized SDFs
//--------------------------------------------------------------------

float globalSceneSDF(vec4 samplePoint, mat4 globalTransMatrix, bool collideWithLights);
float localSceneSDF(vec4 samplePoint);

float sphereSDF(vec4 samplePoint, vec4 center, float radius){
  return geometryDistance(samplePoint, center) - radius;
}

//********************************************************************************************************
//LIGHTING
//********************************************************************************************************

//Essentially we are starting at our sample point then marching to the light
//If we make it to/past the light without hitting anything we return 1
//otherwise the spot does not receive light from that light source
//Based off of Inigo Quilez's soft shadows https://iquilezles.org/www/articles/rmshadows/rmshadows.htm
float shadowMarch(vec4 origin, vec4 dirToLight, float distToLight, mat4 globalTransMatrix){
    float localDepth = EPSILON * 100.0;
    float globalDepth = localDepth;
    vec4 localrO = origin;
    vec4 localrD = dirToLight;
    mat4 fixMatrix = mat4(1.0);
    float k = shadSoft;
    float result = 1.0;
    
    //Local Trace for shadows
    if(renderShadows[0]){
      for(int i = 0; i < MAX_MARCHING_STEPS; i++){
        vec4 localEndPoint = pointOnGeodesic(localrO, localrD, localDepth);

        if(isOutsideCell(localEndPoint, fixMatrix)){
          localrO = geometryNormalize(localEndPoint*fixMatrix, false);
          localrD = geometryFixDirection(localrO, localrD, fixMatrix);
          localDepth = MIN_DIST; 
        }
        else{
          float localDist = min(0.5,localSceneSDF(localEndPoint));
          if(localDist < EPSILON){
            return 0.0;
          }
          localDepth += localDist;
          globalDepth += localDist;
          result = min(result, k*localDist/globalDepth);
          if(globalDepth > distToLight){
            break;
          }
        }
      }  
    }

    //Global Trace for shadows
    if(renderShadows[1]){
      globalDepth = EPSILON * 100.0;
      for(int i = 0; i< MAX_MARCHING_STEPS; i++){
        vec4 globalEndPoint = pointOnGeodesic(origin, dirToLight, globalDepth);
        float globalDist = globalSceneSDF(globalEndPoint, globalTransMatrix, false);
        if(globalDist < EPSILON){
          return 0.0;
        }
        globalDepth += globalDist;
        result = min(result, k*globalDist/globalDepth);
        if(globalDepth > distToLight){
          return result;
        }
      }
      return result;
    }
    return result;
}

vec4 texcube(vec4 samplePoint, mat4 toOrigin){
    float k = 4.0;
    vec4 newSP = samplePoint * toOrigin;
    vec3 p = mod(newSP.xyz,1.0);
    vec3 n = geometryNormalize(N*toOrigin, true).xyz; //Very hacky you are warned
    vec3 m = pow(abs(n), vec3(k));
    vec4 x = texture(tex, p.yz);
    vec4 y = texture(tex, p.zx);
    vec4 z = texture(tex, p.xy);
    return (x*m.x + y*m.y + z*m.z) / (m.x+m.y+m.z);
}


float attenuation(float distToLight, vec4 lightIntensity){
  float att;
  if(attnModel == 1) //Inverse Linear
    att  = 0.75/ (0.01+lightIntensity.w * distToLight);  
  else if(attnModel == 2) //Inverse Square
    att  = 1.0/ (0.01+lightIntensity.w * distToLight* distToLight);
  else if(attnModel == 3) // Inverse Cube
    att = 1.0/ (0.01+lightIntensity.w*distToLight*distToLight*distToLight);
  else if(attnModel == 4) //Physical
    att  = 1.0/ (0.01+lightIntensity.w*cosh(2.0*distToLight)-1.0);
  else //None
    att  = 0.25; //if its actually 1 everything gets washed out
  return att;
}

vec3 lightingCalculations(vec4 SP, vec4 TLP, vec4 V, vec3 baseColor, vec4 lightIntensity, mat4 globalTransMatrix){
  float distToLight = geometryDistance(SP, TLP);
  float att = attenuation(distToLight, lightIntensity);
  //Calculations - Phong Reflection Model
  vec4 L = geometryDirection(SP, TLP);
  vec4 R = 2.0*geometryDot(L, N)*N - L;
  //Calculate Diffuse Component
  float nDotL = max(geometryDot(N, L),0.0);
  vec3 diffuse = lightIntensity.rgb * nDotL;
  //Calculate Shadows
  float shadow = 1.0;
  shadow = shadowMarch(SP, L, distToLight, globalTransMatrix);
  //Calculate Specular Component
  float rDotV = max(geometryDot(R, V),0.0);
  vec3 specular = lightIntensity.rgb * pow(rDotV,10.0);
  //Compute final color
  return att*(shadow*((diffuse*baseColor) + specular));
}

vec3 phongModel(mat4 invObjectBoost, bool isGlobal, mat4 globalTransMatrix){
  //--------------------------------------------
  //Setup Variables
  //--------------------------------------------
  float ambient = 0.1;
  vec3 baseColor = vec3(0.0,1.0,1.0);
  vec4 SP = sampleEndPoint;
  vec4 TLP;
  vec4 V = -sampleTangentVector;

  if(isGlobal){ //this may be possible to move outside function as we already have an if statement for global v. local
    baseColor = texcube(SP, cellBoost * invObjectBoost).xyz; 
  }
  else{
    baseColor = texcube(SP, mat4(1.0)).xyz;
  }

  //Setup up color with ambient component
  vec3 color = baseColor * ambient; 

  //--------------------------------------------
  //Lighting Calculations
  //--------------------------------------------
  //Standard Light Objects
  for(int i = 0; i<NUM_LIGHTS; i++){
    if(lightIntensities[i].w != 0.0){
      TLP = lightPositions[i]*globalTransMatrix;
      color += lightingCalculations(SP, TLP, V, baseColor, lightIntensities[i], globalTransMatrix);
    }
  }

  //Lights for Controllers
  for(int i = 0; i<2; i++){
    if(controllerCount == 0) break; //if there are no controllers do nothing
    else TLP = ORIGIN*controllerBoosts[i]*currentBoost*cellBoost*globalTransMatrix;

    color += lightingCalculations(SP, TLP, V, baseColor, lightIntensities[i+4], globalTransMatrix);

    if(controllerCount == 1) break; //if there is one controller only do one loop
  }

  return color;
}

//********************************************************************************************************
//MATH
//********************************************************************************************************

//-------------------------------------------------------
// Generalized Functions
//-------------------------------------------------------
float geometryDot(vec4 u, vec4 v){
  return u.x*v.x + u.y*v.y + u.z*v.z - u.w*v.w; // Lorentz Dot
}
vec4 geometryNormalize(vec4 u, bool toTangent){
  return u/geometryNorm(u);
}
float geometryDistance(vec4 u, vec4 v){
  float bUV = -geometryDot(u,v);
  return acosh(bUV);
}

//Given two positions find the unit tangent vector at the first that points to the second
vec4 geometryDirection(vec4 u, vec4 v){
  vec4 w = v + geometryDot(u,v)*u;
  return geometryNormalize(w, true);
}

//calculate the new direction vector (v) for the continuation of the ray from the new ray origin (u)
//having moved by fix matrix
vec4 geometryFixDirection(vec4 u, vec4 v, mat4 fixMatrix){
  return geometryDirection(u, v*fixMatrix); 
}

//-------------------------------------------------------
//Hyperboloid Functions
//-------------------------------------------------------

vec4 projectToKlein(vec4 v){
  return v/v.w;
}

// Get point at distance dist on the geodesic from u in the direction vPrime
vec4 pointOnGeodesic(vec4 u, vec4 vPrime, float dist){
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

//********************************************************************************************************
//LOCAL SCENE
//********************************************************************************************************

float localSceneSDF(vec4 samplePoint) {
    float sphere = 0.0;
    if(cut1 == 1) {
        sphere = sphereSDF(samplePoint, cellPosition, cellSurfaceOffset);
    }
    else if(cut1 == 2) {
        sphere = horosphereHSDF(samplePoint, cellPosition, cellSurfaceOffset);
    }
    else if(cut1 == 3) {
        sphere = geodesicPlaneHSDF(samplePoint, cellPosition, cellSurfaceOffset);
    }

    float vertexSphere = 0.0;
    if(cut4 == 1) {
        vertexSphere = sphereSDF(abs(samplePoint), vertexPosition, vertexSurfaceOffset);
    }
    else if(cut4 == 2) {
        vertexSphere = horosphereHSDF(abs(samplePoint), vertexPosition, vertexSurfaceOffset);
    }
    else if(cut4 == 3) {
        vertexSphere = geodesicPlaneHSDF(abs(samplePoint), vertexPosition, vertexSurfaceOffset);
    }

    float final = -unionSDF(vertexSphere,sphere);
    return final;
}

//********************************************************************************************************
//FRAGMENT
//********************************************************************************************************

//NORMAL FUNCTIONS ++++++++++++++++++++++++++++++++++++++++++++++++++++
vec4 estimateNormal(vec4 p) { // normal vector is in tangent hyperplane to hyperboloid at p
    // float denom = sqrt(1.0 + p.x*p.x + p.y*p.y + p.z*p.z);  // first, find basis for that tangent hyperplane
    float newEp = EPSILON * 10.0;
    vec4 basis_x = geometryNormalize(vec4(p.w,0.0,0.0,p.x), true);  // dw/dx = x/w on hyperboloid
    vec4 basis_y = vec4(0.0,p.w,0.0,p.y);  // dw/dy = y/denom
    vec4 basis_z = vec4(0.0,0.0,p.w,p.z);  // dw/dz = z/denom  /// note that these are not orthonormal!
    basis_y = geometryNormalize(basis_y - geometryDot(basis_y, basis_x)*basis_x, true); // need to Gram Schmidt
    basis_z = geometryNormalize(basis_z - geometryDot(basis_z, basis_x)*basis_x - geometryDot(basis_z, basis_y)*basis_y, true);
    return geometryNormalize(
        basis_x * (localSceneSDF(p + newEp*basis_x) - localSceneSDF(p - newEp*basis_x)) +
        basis_y * (localSceneSDF(p + newEp*basis_y) - localSceneSDF(p - newEp*basis_y)) +
        basis_z * (localSceneSDF(p + newEp*basis_z) - localSceneSDF(p - newEp*basis_z)),
        true
    );
}

vec4 getRayPoint(vec2 resolution, vec2 fragCoord, bool isRight){ //creates a point that our ray will go through
    if(isStereo == 1){
      resolution.x = resolution.x * 0.5;
      if(isRight) { fragCoord.x = fragCoord.x - resolution.x; }
    }
    vec2 xy = 0.2*((fragCoord - 0.5*resolution)/resolution.x);
    float z = 0.1/tan(radians(fov*0.5));
    vec4 p =  geometryNormalize(vec4(xy,-z,1.0), false);
    return p;
}

bool isOutsideSimplex(vec4 samplePoint, out mat4 fixMatrix){
  vec4 kleinSamplePoint = projectToKlein(samplePoint);
  for(int i=0; i<4; i++){
    vec3 normal = simplexMirrorsKlein[i].xyz;
    vec3 offsetSample = kleinSamplePoint.xyz - normal * simplexMirrorsKlein[i].w;  // Deal with any offset.
    if( dot(offsetSample, normal) > 1e-7 ) {
      fixMatrix = invGenerators[i];
      return true;
    }
  }
  return false;
}

// This function is intended to be geometry-agnostic.
bool isOutsideCell(vec4 samplePoint, out mat4 fixMatrix){
  if( useSimplex ) {
    return isOutsideSimplex( samplePoint, fixMatrix );
  }

  vec4 kleinSamplePoint = projectToKlein(samplePoint);
  if(kleinSamplePoint.x > halfCubeWidthKlein){
    fixMatrix = invGenerators[0];
    return true;
  }
  if(kleinSamplePoint.x < -halfCubeWidthKlein){
    fixMatrix = invGenerators[1];
    return true;
  }
  if(kleinSamplePoint.y > halfCubeWidthKlein){
    fixMatrix = invGenerators[2];
    return true;
  }
  if(kleinSamplePoint.y < -halfCubeWidthKlein){
    fixMatrix = invGenerators[3];
    return true;
  }
  if(kleinSamplePoint.z > halfCubeWidthKlein){
    fixMatrix = invGenerators[4];
    return true;
  }
  if(kleinSamplePoint.z < -halfCubeWidthKlein){
    fixMatrix = invGenerators[5];
    return true;
  }
  return false;
}

void raymarch(vec4 rO, vec4 rD, out mat4 totalFixMatrix){
  float globalDepth = MIN_DIST; float localDepth = globalDepth;
  vec4 localrO = rO; vec4 localrD = rD;
  totalFixMatrix = mat4(1.0);
  mat4 fixMatrix = mat4(1.0);
  
  // Trace the local scene, then the global scene:
  for(int i = 0; i< maxSteps; i++){
    if(globalDepth >= maxDist){
      //when we break it's as if we reached our max marching steps
      break;
    }
    vec4 localEndPoint = pointOnGeodesic(localrO, localrD, localDepth);
    if(isOutsideCell(localEndPoint, fixMatrix)){
      totalFixMatrix *= fixMatrix;
      localrO = geometryNormalize(localEndPoint*fixMatrix, false);
      localrD = geometryFixDirection(localrO, localrD, fixMatrix); 
      localDepth = MIN_DIST;
    }
    else{
      float localDist = min(0.5,localSceneSDF(localEndPoint));
      if(localDist < EPSILON){
        hitWhich = 3;
        sampleEndPoint = localEndPoint;
        sampleTangentVector = tangentVectorOnGeodesic(localrO, localrD, localDepth);
        break;
      }
      localDepth += localDist;
      globalDepth += localDist;
    }
  }
  
  // Set localDepth to our new max tracing distance:
  localDepth = min(globalDepth, maxDist);
  globalDepth = MIN_DIST;
  for(int i = 0; i< maxSteps; i++){
    vec4 globalEndPoint = pointOnGeodesic(rO, rD, globalDepth);
    float globalDist = globalSceneSDF(globalEndPoint, invCellBoost, true);
    if(globalDist < EPSILON){
      // hitWhich has been set by globalSceneSDF
      totalFixMatrix = mat4(1.0);
      sampleEndPoint = globalEndPoint;
      sampleTangentVector = tangentVectorOnGeodesic(rO, rD, globalDepth);
      return;
    }
    globalDepth += globalDist;
    if(globalDepth >= localDepth){
      break;
    }
  }
}

void main(){
  vec4 rayOrigin = ORIGIN;
  
  //stereo translations
  bool isRight = gl_FragCoord.x/screenResolution.x > 0.5;
  vec4 rayDirV = getRayPoint(screenResolution, gl_FragCoord.xy, isRight);
  
  if(isStereo == 1){
    if(isRight){
      rayOrigin *= stereoBoosts[1];
      rayDirV *= stereoBoosts[1];
    }
    else{
      rayOrigin *= stereoBoosts[0];
      rayDirV *= stereoBoosts[0];
    }
    
  }

  rayOrigin *= currentBoost;
  rayDirV *= currentBoost;
  //generate direction then transform to hyperboloid ------------------------
  vec4 rayDirVPrime = geometryDirection(rayOrigin, rayDirV);
  //get our raymarched distance back ------------------------
  mat4 totalFixMatrix = mat4(1.0);
  raymarch(rayOrigin, rayDirVPrime, totalFixMatrix);

  //Based on hitWhich decide whether we hit a global object, local object, or nothing
  if(hitWhich == 0){ //Didn't hit anything ------------------------
    out_FragColor = vec4(0.0);
    return;
  }
  else if(hitWhich == 1){ // global lights
    out_FragColor = vec4(globalLightColor.rgb, 1.0);
    return;
  }
  else{ // objects
    N = estimateNormal(sampleEndPoint);
    vec3 color;
    mat4 globalTransMatrix = invCellBoost * totalFixMatrix;
    if(hitWhich == 2){ // global objects
      color = phongModel(inverse(globalObjectBoost), true, globalTransMatrix);
    }else{ // local objects
      color = phongModel(mat4(1.0), false, globalTransMatrix);
    }
    out_FragColor = vec4(color, 1.0);
  }
}