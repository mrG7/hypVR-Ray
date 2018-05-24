//--------------------------------------------
//Global Constants
//--------------------------------------------
const int MAX_MARCHING_STEPS = 127;
const float MIN_DIST = 0.0;
const float MAX_DIST = 10.0;
const float EPSILON = 0.0001;
const vec4 ORIGIN = vec4(0,0,0,1);
//--------------------------------------------
//Generated Constants
//--------------------------------------------
const float halfIdealCubeWidthKlein = 0.5773502692;
const vec4 idealCubeCornerKlein = vec4(halfIdealCubeWidthKlein, halfIdealCubeWidthKlein, halfIdealCubeWidthKlein, 1.0);
//--------------------------------------------
//Global Constants
//--------------------------------------------
uniform int isStereo;
uniform mat4 cameraProjection;
uniform vec2 screenResolution;
uniform vec4 cameraQuat;
uniform float fov;
uniform mat4 generators[6];
uniform mat4 invGenerators[6];
uniform mat4 currentBoost;
uniform mat4 leftCurrentBoost;
uniform mat4 rightCurrentBoost;
uniform vec4 leftEyeRotation;
uniform vec4 rightEyeRotation;
uniform mat4 cellBoost;
uniform mat4 invCellBoost;
uniform int maxSteps;
//--------------------------------------------
//Lighting Variables & Global Object Variables
//--------------------------------------------
uniform vec4 lightPositions[8];
uniform vec4 lightIntensities[8]; //w component is the light's attenuation
uniform int attnModel;
uniform sampler2D texture;
uniform mat4 globalObjectBoosts[8];
uniform mat4 invGlobalObjectBoosts[8];
uniform vec3 globalObjectRadii[8];
uniform int globalObjectTypes[8];
//--------------------------------------------
//Scene Dependent Variables
//--------------------------------------------
uniform vec4 halfCubeDualPoints[3];
uniform float halfCubeWidthKlein;
uniform float sphereRad;
uniform float tubeRad;
uniform float horosphereSize;
uniform float planeOffset;

// The type of cut (1=sphere, 2=horosphere, 3=plane) for the vertex opposite the fundamental simplex's 4th mirror.
// These integers match our values for the geometry of the honeycomb vertex figure.
// We'll need more of these later when we support more symmetry groups.
uniform int cut4;

//Quaternion Math
vec3 qtransform( vec4 q, vec3 v ){
  return v + 2.0*cross(cross(v, -q.xyz ) + q.w*v, -q.xyz);
}

//Raymarch Functions
float unionSDF(float d1, float d2){
  return min(d1, d2);
}

