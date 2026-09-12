using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

namespace UnityEditor.Rendering.PostProcessing
{
    [PostProcessEditor(typeof(AutoExposure))]
    internal sealed class AutoExposureEditor : PostProcessEffectEditor<AutoExposure>
    {
        SerializedParameterOverride m_Filtering;

        SerializedParameterOverride m_RefLuminance;
        SerializedParameterOverride m_Sensitivity;
        SerializedParameterOverride m_KeyValue;

        SerializedParameterOverride m_EyeAdaptation;
        SerializedParameterOverride m_SpeedUp;
        SerializedParameterOverride m_SpeedDown;

        public override void OnEnable()
        {
            m_Filtering = FindParameterOverride(x => x.filtering);

            m_RefLuminance = FindParameterOverride(x => x.refLuminance);
            m_Sensitivity = FindParameterOverride(x => x.sensitivity);
            m_KeyValue = FindParameterOverride(x => x.keyValue);

            m_EyeAdaptation = FindParameterOverride(x => x.eyeAdaptation);
            m_SpeedUp = FindParameterOverride(x => x.speedUp);
            m_SpeedDown = FindParameterOverride(x => x.speedDown);
        }

        public override void OnInspectorGUI()
        {
            if (!SystemInfo.supportsComputeShaders)
                EditorGUILayout.HelpBox("Auto exposure requires compute shader support.", MessageType.Warning);

            EditorUtilities.DrawHeaderLabel("Exposure");

            PropertyField(m_Filtering);
            PropertyField(m_RefLuminance);
            PropertyField(m_Sensitivity);
            PropertyField(m_KeyValue);

            EditorGUILayout.Space();
            EditorUtilities.DrawHeaderLabel("Adaptation");

            PropertyField(m_EyeAdaptation);

            if (m_EyeAdaptation.value.intValue == (int)EyeAdaptation.Progressive)
            {
                PropertyField(m_SpeedUp);
                PropertyField(m_SpeedDown);
            }
        }
    }
}
