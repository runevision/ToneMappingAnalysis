using System;
using System.Linq.Expressions;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

namespace UnityEditor.Rendering.PostProcessing
{
    /// <summary>
    /// Small wrapper on top of <see cref="Editor"/> to ease the access of the underlying component
    /// and its serialized fields.
    /// </summary>
    /// <typeparam name="T">The type of the target component to make an editor for</typeparam>
    /// <example>
    /// <code>
    /// public class MyMonoBehaviour : MonoBehaviour
    /// {
    ///     public float myProperty = 1.0f;
    /// }
    ///
    /// [CustomEditor(typeof(MyMonoBehaviour))]
    /// public sealed class MyMonoBehaviourEditor : BaseEditor&lt;MyMonoBehaviour&gt;
    /// {
    ///     SerializedProperty m_MyProperty;
    ///
    ///     void OnEnable()
    ///     {
    ///         m_MyProperty = FindProperty(x => x.myProperty);
    ///     }
    ///
    ///     public override void OnInspectorGUI()
    ///     {
    ///         EditorGUILayout.PropertyField(m_MyProperty);
    ///     }
    /// }
    /// </code>
    /// </example>
    public class BaseEditor<T> : Editor
        where T : MonoBehaviour
    {
        /// <summary>
        /// The target component.
        /// </summary>
        protected T m_Target
        {
            get { return (T)target; }
        }

        /// <summary>
        /// Find a serialized property using an expression instead of a string. This is safer as it
        /// helps avoiding typos and make code refactoring easier.
        /// </summary>
        /// <typeparam name="TValue">The serialized value type</typeparam>
        /// <param name="expr">The expression to parse to reach the property</param>
        /// <returns>A <see cref="SerializedProperty"/> or <c>null</c> if none was found</returns>
        protected SerializedProperty FindProperty<TValue>(Expression<Func<T, TValue>> expr)
        {
            return serializedObject.FindProperty(RuntimeUtilities.GetFieldPath(expr));
        }
    }
}
