/**
 * Tiresias Client - iPhone Camera Streaming
 * Streams camera feed to MacBook edge server via WebSocket
 */

import React, { useEffect, useRef, useState, useCallback } from 'react';
import {
  StyleSheet,
  View,
  Text,
  StatusBar,
  TouchableOpacity,
  Alert,
} from 'react-native';
import {
  Camera,
  useCameraDevice,
  useCameraPermission,
  useFrameProcessor,
} from 'react-native-vision-camera';
import { Worklets } from 'react-native-worklets-core';

// Edge server configuration - connect via WiFi to Mac's IP
const EDGE_SERVER_URL = 'ws://127.0.0.1:8000/ws/video';

function App(): React.JSX.Element {
  const { hasPermission, requestPermission } = useCameraPermission();
  const device = useCameraDevice('back');
  const cameraRef = useRef<Camera>(null);
  
  const [isConnected, setIsConnected] = useState(false);
  const [isStreaming, setIsStreaming] = useState(false);
  const [fps, setFps] = useState(0);
  
  const wsRef = useRef<WebSocket | null>(null);
  const frameCountRef = useRef(0);
  const lastFpsUpdateRef = useRef(Date.now());

  // Request camera permission on mount
  useEffect(() => {
    if (!hasPermission) {
      requestPermission();
    }
  }, [hasPermission, requestPermission]);

  // Connect to WebSocket server
  const connectWebSocket = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    console.log('🔌 Connecting to edge server...');
    const ws = new WebSocket(EDGE_SERVER_URL);

    ws.onopen = () => {
      console.log('🟢 Connected to edge server');
      setIsConnected(true);
    };

    ws.onclose = (e) => {
      console.log('🔴 Disconnected from edge server:', e.reason);
      setIsConnected(false);
      setIsStreaming(false);
    };

    ws.onerror = (e) => {
      console.error('❌ WebSocket error:', e.message);
      Alert.alert(
        'Connection Error',
        'Cannot connect to edge server. Make sure:\n\n1. Edge server is running on Mac\n2. USB tunnel is active (iproxy 8000 8000)'
      );
    };

    wsRef.current = ws;
  }, []);

  // Disconnect WebSocket
  const disconnectWebSocket = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    setIsConnected(false);
    setIsStreaming(false);
  }, []);

  // Take photo and send via WebSocket
  const captureAndSend = useCallback(async () => {
    if (!cameraRef.current || !wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      return;
    }

    try {
      // Capture photo as JPEG
      const photo = await cameraRef.current.takePhoto({
        flash: 'off',
        enableShutterSound: false,
      });

      // Read file as base64 and send
      const response = await fetch(`file://${photo.path}`);
      const blob = await response.blob();
      
      // Convert blob to ArrayBuffer and send as binary
      const arrayBuffer = await blob.arrayBuffer();
      wsRef.current.send(arrayBuffer);

      // Update FPS counter
      frameCountRef.current++;
      const now = Date.now();
      if (now - lastFpsUpdateRef.current >= 1000) {
        setFps(frameCountRef.current);
        frameCountRef.current = 0;
        lastFpsUpdateRef.current = now;
      }
    } catch (error) {
      console.error('Error capturing/sending frame:', error);
    }
  }, []);

  // Streaming loop
  useEffect(() => {
    let intervalId: NodeJS.Timeout | null = null;

    if (isStreaming && isConnected) {
      // Capture at ~10 FPS (100ms interval)
      intervalId = setInterval(captureAndSend, 100);
    }

    return () => {
      if (intervalId) {
        clearInterval(intervalId);
      }
    };
  }, [isStreaming, isConnected, captureAndSend]);

  // Toggle streaming
  const toggleStreaming = useCallback(() => {
    if (!isConnected) {
      connectWebSocket();
      // Start streaming after connection
      setTimeout(() => setIsStreaming(true), 500);
    } else if (isStreaming) {
      setIsStreaming(false);
    } else {
      setIsStreaming(true);
    }
  }, [isConnected, isStreaming, connectWebSocket]);

  // Render permission request
  if (!hasPermission) {
    return (
      <View style={styles.container}>
        <StatusBar barStyle="light-content" />
        <Text style={styles.message}>Camera permission required</Text>
        <TouchableOpacity style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>Grant Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // Render no device error
  if (!device) {
    return (
      <View style={styles.container}>
        <StatusBar barStyle="light-content" />
        <Text style={styles.message}>No camera device found</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" />
      
      {/* Camera Preview */}
      <Camera
        ref={cameraRef}
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={true}
        photo={true}
      />

      {/* Status Overlay */}
      <View style={styles.overlay}>
        <View style={styles.statusBar}>
          <View style={[styles.statusDot, { backgroundColor: isConnected ? '#00ff00' : '#ff0000' }]} />
          <Text style={styles.statusText}>
            {isConnected ? 'Connected' : 'Disconnected'}
          </Text>
          {isStreaming && (
            <Text style={styles.fpsText}>{fps} FPS</Text>
          )}
        </View>

        <Text style={styles.title}>TIRESIAS</Text>
        <Text style={styles.subtitle}>Vision Assist</Text>
      </View>

      {/* Control Button */}
      <View style={styles.controls}>
        <TouchableOpacity
          style={[
            styles.streamButton,
            { backgroundColor: isStreaming ? '#ff4444' : '#44ff44' }
          ]}
          onPress={toggleStreaming}
        >
          <Text style={styles.streamButtonText}>
            {isStreaming ? 'STOP' : 'START'}
          </Text>
        </TouchableOpacity>

        {isConnected && (
          <TouchableOpacity
            style={styles.disconnectButton}
            onPress={disconnectWebSocket}
          >
            <Text style={styles.disconnectButtonText}>Disconnect</Text>
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  message: {
    color: '#fff',
    fontSize: 18,
    textAlign: 'center',
    marginBottom: 20,
  },
  button: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 30,
    paddingVertical: 15,
    borderRadius: 10,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  overlay: {
    position: 'absolute',
    top: 60,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 15,
    paddingVertical: 8,
    borderRadius: 20,
    marginBottom: 20,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 8,
  },
  statusText: {
    color: '#fff',
    fontSize: 14,
  },
  fpsText: {
    color: '#00ff00',
    fontSize: 14,
    marginLeft: 15,
    fontWeight: 'bold',
  },
  title: {
    color: '#fff',
    fontSize: 32,
    fontWeight: 'bold',
    textShadowColor: 'rgba(0,0,0,0.8)',
    textShadowOffset: { width: 2, height: 2 },
    textShadowRadius: 4,
  },
  subtitle: {
    color: '#aaa',
    fontSize: 16,
    marginTop: 5,
  },
  controls: {
    position: 'absolute',
    bottom: 50,
    alignItems: 'center',
  },
  streamButton: {
    width: 100,
    height: 100,
    borderRadius: 50,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
  streamButtonText: {
    color: '#000',
    fontSize: 18,
    fontWeight: 'bold',
  },
  disconnectButton: {
    marginTop: 20,
    paddingHorizontal: 20,
    paddingVertical: 10,
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderRadius: 10,
  },
  disconnectButtonText: {
    color: '#fff',
    fontSize: 14,
  },
});

export default App;
