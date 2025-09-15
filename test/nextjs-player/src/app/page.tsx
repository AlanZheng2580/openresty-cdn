"use client";

import { useState, useRef } from 'react';
import Hls from 'hls.js';

type AuthMethod = 'apiKey' | 'token';

const HLSPlayer = () => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const hlsRef = useRef<Hls | null>(null);

  const [authMethod, setAuthMethod] = useState<AuthMethod>('apiKey');
  const [apiKey, setApiKey] = useState('58028419ac995b94cc7750b7c5e3a117');
  const [token, setToken] = useState('URLPrefix=...:Expires=...:KeyName=...:Signature=...');
  const [videoUrl, setVideoUrl] = useState('http://localhost:8080/minio/bucket-a/2024summer/2024summer_nice_song_0/playlist.m3u8');

  const loadVideo = () => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
    }

    const video = videoRef.current;
    if (!video) return;

    const hls = new Hls({
      xhrSetup: (xhr) => {
        if (authMethod === 'apiKey') {
          xhr.setRequestHeader('X-SECDN-API-KEY', apiKey);
        } else if (authMethod === 'token') {
          xhr.setRequestHeader('X-SECDN-Token', token);
        }
      },
    });

    hls.loadSource(videoUrl);
    hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      video.play();
    });

    hlsRef.current = hls;
  };

  return (
    <div className="w-full max-w-4xl mx-auto p-4">
      <h1 className="text-2xl font-bold text-center my-4 text-gray-900">OpenResty CDN Player</h1>
      <div className="space-y-4 p-4 bg-gray-100 rounded-lg border">
        
        {/* URL Input */}
        <div>
          <label htmlFor="video-url" className="block text-sm font-medium text-gray-800">M3U8 URL</label>
          <input
            type="text"
            id="video-url"
            value={videoUrl}
            onChange={(e) => setVideoUrl(e.target.value)}
            className="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm text-gray-900"
          />
        </div>

        {/* Auth Method Selection */}
        <div>
          <label className="block text-sm font-medium text-gray-800">Auth Method</label>
          <div className="mt-2 flex items-center space-x-4">
            <label className="inline-flex items-center">
              <input type="radio" className="form-radio" name="authMethod" value="apiKey" checked={authMethod === 'apiKey'} onChange={() => setAuthMethod('apiKey')} />
              <span className="ml-2 text-gray-800">API Key</span>
            </label>
            <label className="inline-flex items-center">
              <input type="radio" className="form-radio" name="authMethod" value="token" checked={authMethod === 'token'} onChange={() => setAuthMethod('token')} />
              <span className="ml-2 text-gray-800">Token</span>
            </label>
          </div>
        </div>

        {/* Conditional Inputs */}
        {authMethod === 'apiKey' ? (
          <div>
            <label htmlFor="api-key" className="block text-sm font-medium text-gray-800">X-SECDN-API-KEY</label>
            <input
              type="text"
              id="api-key"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              className="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm text-gray-900"
            />
          </div>
        ) : (
          <div>
            <label htmlFor="token" className="block text-sm font-medium text-gray-800">X-SECDN-Token</label>
            <textarea
              id="token"
              rows={3}
              value={token}
              onChange={(e) => setToken(e.target.value)}
              className="mt-1 block w-full px-3 py-2 bg-white border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm font-mono text-gray-900"
            />
          </div>
        )}

        <button
          onClick={loadVideo}
          className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Load Video
        </button>
      </div>

      <video ref={videoRef} controls className="w-full h-auto bg-black mt-4" />

      <div className="mt-4 p-2 text-center text-xs text-gray-700">
        <p>If the video does not load, check the browser's developer console (Network and Console tabs) for errors.</p>
      </div>
    </div>
  );
};

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-2 bg-gray-50">
      <HLSPlayer />
    </main>
  );
}